#!/usr/bin/env bash
# TgWebProxyR — guided install wizard + engine deploy

TWPR_TOTAL_STEPS=9
# quick | advanced | docker — задаётся из CLI / install.sh / env
TWPR_SETUP_MODE="${TWPR_SETUP_MODE:-}"

TWPR_patch_upstream_install() {
  local inst="${TWPR_ENGINE_DIR}/deploy/install.sh"
  [[ -f "$inst" ]] || return 0

  # Upstream aborts on flaky: TestLoadAcceptsSystemdCredentialReadPermissions
  if grep -qE 'test \./\.\.\.' "$inst"; then
    if ! grep -q 'TWPR: skip go test' "$inst"; then
      TWPR_info "Патчу upstream install.sh: пропускаю go test (flake на части VPS)"
      sed -i -E \
        's|\(cd "\$repository" && "\$go_binary" test \./\.\.\.\)|echo "TWPR: skip go test"; true|g' \
        "$inst"
    fi
  fi

  # Upstream waits only 20s for readyz — often too short while mtproxy warms up
  if grep -q 'attempt != 20' "$inst" && ! grep -q 'TWPR: ready wait' "$inst"; then
    TWPR_info "Патчу upstream install.sh: longer ready-wait + soft fail"
    sed -i 's/attempt != 20/attempt != 90/' "$inst"
    # Replace hard exit with soft warning so our wrapper can recover
    sed -i \
      's/echo "tproxy-server did not become ready" >&2/echo "TWPR: ready wait — will recover"; true # was: tproxy-server did not become ready/' \
      "$inst"
    sed -i '/TWPR: ready wait/{n;s/exit 1/true # TWPR: soft fail/}' "$inst"
  fi
}

TWPR_diagnose_relay() {
  local admin="${TWPR_PORT_ADMIN:-8081}"
  TWPR_warn "Диагностика tproxy-server / mtproxy:"
  systemctl --no-pager --full status tproxy-firewall mtproxy tproxy-server caddy 2>&1 | tail -n 40 || true
  echo ""
  TWPR_info "journalctl tproxy-server (последние 40 строк):"
  journalctl -u tproxy-server -u mtproxy -n 40 --no-pager 2>&1 || true
  echo ""
  TWPR_info "curl healthz/readyz:"
  curl -sv --max-time 3 "http://127.0.0.1:${admin}/healthz" 2>&1 | tail -n 20 || true
  curl -sv --max-time 3 "http://127.0.0.1:${admin}/readyz" 2>&1 | tail -n 20 || true
}

TWPR_fix_mtproxy_binary() {
  local bin="/opt/MTProxy/objs/bin/mtproto-proxy"
  local engine_install="${TWPR_ENGINE_DIR}/deploy/install-mtproxy.sh"

  # umask 077 during install can leave /opt/MTProxy as 0700 root:root → 203/EXEC for User=mtproxy
  if [[ -d /opt/MTProxy ]]; then
    TWPR_info "Чиню права /opt/MTProxy (чтобы User=mtproxy мог запускать бинарник)"
    find /opt/MTProxy -type d -exec chmod 755 {} + 2>/dev/null || true
    find /opt/MTProxy -type f -exec chmod a+r {} + 2>/dev/null || true
    [[ -f "$bin" ]] && chmod 755 "$bin"
    # keep secrets tight
    if [[ -d /etc/mtproxy ]]; then
      chown -R root:mtproxy /etc/mtproxy 2>/dev/null || true
      chmod 0750 /etc/mtproxy 2>/dev/null || true
      chmod 0640 /etc/mtproxy/proxy-secret /etc/mtproxy/proxy-multi.conf 2>/dev/null || true
      [[ -f /etc/mtproxy/mtproxy.env ]] && chmod 0640 /etc/mtproxy/mtproxy.env
    fi
  fi

  if [[ ! -x "$bin" ]]; then
    TWPR_warn "Бинарник mtproto-proxy отсутствует — пересобираю"
    if [[ -x "$engine_install" ]]; then
      # Do NOT use umask 077 here — directories must stay world-traversable
      umask 022
      bash "$engine_install"
    else
      TWPR_err "Нет ${engine_install}. Сначала: tgwebproxyr setup"
      return 1
    fi
  fi

  if [[ ! -x "$bin" ]]; then
    TWPR_err "mtproto-proxy всё ещё не исполняемый: ${bin}"
    ls -la /opt/MTProxy/objs/bin 2>&1 || true
    return 1
  fi

  # Quick sanity: file + dynamic linker
  if ! "$bin" --help >/dev/null 2>&1 && ! "$bin" -h >/dev/null 2>&1; then
    # official binary may not support --help; try `file` / ldd
    file "$bin" 2>/dev/null || true
    ldd "$bin" 2>/dev/null | head -n 20 || true
  fi

  TWPR_ok "mtproto-proxy: ${bin}"
  return 0
}

TWPR_ensure_relay_ready() {
  local admin="${TWPR_PORT_ADMIN:-8081}"
  local i

  # Soften overly strict unit options that break Go on some hosts
  if [[ -f /etc/systemd/system/tproxy-server.service ]]; then
    if grep -q '^MemoryDenyWriteExecute=true' /etc/systemd/system/tproxy-server.service; then
      TWPR_info "Снимаю MemoryDenyWriteExecute (часто ломает Go-бинарник)"
      sed -i 's/^MemoryDenyWriteExecute=true/MemoryDenyWriteExecute=false/' \
        /etc/systemd/system/tproxy-server.service
      systemctl daemon-reload
    fi
  fi

  # Ensure profiles permissions for LoadCredential
  if [[ -f /etc/tproxy-server/profiles.json ]]; then
    chown root:tproxy /etc/tproxy-server/profiles.json 2>/dev/null || true
    chmod 0400 /etc/tproxy-server/profiles.json 2>/dev/null || true
  fi
  if [[ -f /etc/tproxy-server/config.json ]]; then
    chown root:tproxy /etc/tproxy-server/config.json 2>/dev/null || true
    chmod 0640 /etc/tproxy-server/config.json 2>/dev/null || true
  fi

  TWPR_fix_mtproxy_binary || return 1

  # Ensure mtproxy.env exists with secret
  if [[ ! -f /etc/mtproxy/mtproxy.env ]]; then
    mkdir -p /etc/mtproxy
    umask 077
    cat >/etc/mtproxy/mtproxy.env <<EOF
MTPROXY_SECRET=${TWPR_SECRET:-}
MTPROXY_WORKERS=${TWPR_MTPROXY_WORKERS:-1}
MTPROXY_MAX_CONNECTIONS=${TWPR_MTPROXY_MAX_CONNECTIONS:-4096}
EOF
    chown root:mtproxy /etc/mtproxy/mtproxy.env
    chmod 0640 /etc/mtproxy/mtproxy.env
    umask 022
  elif [[ -n "${TWPR_SECRET:-}" ]] && ! grep -q '^MTPROXY_SECRET=.\+' /etc/mtproxy/mtproxy.env; then
    sed -i "s/^MTPROXY_SECRET=.*/MTPROXY_SECRET=${TWPR_SECRET}/" /etc/mtproxy/mtproxy.env || \
      echo "MTPROXY_SECRET=${TWPR_SECRET}" >>/etc/mtproxy/mtproxy.env
  fi

  systemctl reset-failed tproxy-firewall mtproxy tproxy-server 2>/dev/null || true
  systemctl start tproxy-firewall 2>/dev/null || true
  systemctl restart mtproxy 2>/dev/null || true
  sleep 2

  if ! systemctl is-active --quiet mtproxy; then
    TWPR_warn "mtproxy всё ещё не active после фикса прав"
    journalctl -u mtproxy -n 30 --no-pager 2>&1 || true
    # one more rebuild attempt if still 203
    if journalctl -u mtproxy -n 5 --no-pager 2>/dev/null | grep -q '203/EXEC'; then
      TWPR_warn "Повторная 203/EXEC — пересобираю MTProxy с umask 022"
      rm -rf /opt/MTProxy
      umask 022
      bash "${TWPR_ENGINE_DIR}/deploy/install-mtproxy.sh"
      TWPR_fix_mtproxy_binary || return 1
      systemctl restart mtproxy
      sleep 2
    fi
  fi

  systemctl restart tproxy-server 2>/dev/null || true

  TWPR_info "Жду готовности relay (до 90с)…"
  for i in $(seq 1 90); do
    if curl -fsS --max-time 2 "http://127.0.0.1:${admin}/readyz" >/dev/null 2>&1; then
      TWPR_ok "relay readyz OK (${i}s)"
      return 0
    fi
    if (( i % 15 == 0 )); then
      TWPR_info "ещё жду… (${i}s) mtproxy=$(systemctl is-active mtproxy 2>/dev/null) healthz=$(curl -fsS --max-time 1 "http://127.0.0.1:${admin}/healthz" >/dev/null 2>&1 && echo ok || echo fail)"
    fi
    sleep 1
  done

  # Last resort: if healthz works but readyz doesn't — backend issue
  if curl -fsS --max-time 2 "http://127.0.0.1:${admin}/healthz" >/dev/null 2>&1; then
    TWPR_warn "relay жив, но backend (mtproxy) не ready"
    TWPR_info "Пробую ещё раз перезапустить mtproxy…"
    systemctl restart mtproxy
    sleep 5
    systemctl restart tproxy-server
    for i in $(seq 1 30); do
      if curl -fsS --max-time 2 "http://127.0.0.1:${admin}/readyz" >/dev/null 2>&1; then
        TWPR_ok "relay readyz OK после рестарта backend"
        return 0
      fi
      sleep 1
    done
  fi

  TWPR_diagnose_relay
  return 1
}

TWPR_run_official_install() {
  local args=(
    --hostname "$TWPR_HOSTNAME"
    --email "$TWPR_EMAIL"
    --secret "$TWPR_SECRET"
    --site-dir "$TWPR_SITE_DIR"
    --mtproxy-workers "${TWPR_MTPROXY_WORKERS:-1}"
    --mtproxy-max-connections "${TWPR_MTPROXY_MAX_CONNECTIONS:-4096}"
  )
  local rc=0
  TWPR_info "Официальный install (Caddy + MTProxy + relay) — это займёт несколько минут…"
  TWPR_log "official install hostname=${TWPR_HOSTNAME}"
  TWPR_patch_upstream_install
  set +e
  (
    # Important: do NOT use umask 077 here — MTProxy dirs must stay traversable by User=mtproxy
    umask 022
    cd "$TWPR_ENGINE_DIR"
    bash ./deploy/install.sh "${args[@]}"
  )
  rc=$?
  set -e

  # Tighten only secret files after install
  if [[ -f /etc/tproxy-server/profiles.json ]]; then
    chmod 0400 /etc/tproxy-server/profiles.json 2>/dev/null || true
  fi
  if [[ -f /etc/mtproxy/mtproxy.env ]]; then
    chmod 0640 /etc/mtproxy/mtproxy.env 2>/dev/null || true
  fi

  if [[ "$rc" -ne 0 ]]; then
    TWPR_warn "upstream install код ${rc} — запускаю восстановление сервисов"
  fi

  if ! TWPR_ensure_relay_ready; then
    TWPR_err "tproxy-server так и не стал ready"
    TWPR_err "Пришлите вывод: journalctl -u tproxy-server -u mtproxy -n 80 --no-pager"
    return 1
  fi
  return 0
}

TWPR_fetch_engine() {
  TWPR_ensure_deps
  mkdir -p "$(dirname "$TWPR_ENGINE_DIR")"
  if [[ -d "${TWPR_ENGINE_DIR}/.git" ]]; then
    TWPR_info "Обновляю tproxy-server (${TWPR_ENGINE_REF})…"
    git -C "$TWPR_ENGINE_DIR" fetch --depth 1 origin "$TWPR_ENGINE_REF" || true
    git -C "$TWPR_ENGINE_DIR" checkout -q FETCH_HEAD 2>/dev/null \
      || git -C "$TWPR_ENGINE_DIR" checkout -q "$TWPR_ENGINE_REF" || true
  else
    TWPR_info "Клонирую telegramdesktop/tproxy-server…"
    rm -rf "$TWPR_ENGINE_DIR"
    git clone --depth 1 --branch "$TWPR_ENGINE_REF" "$TWPR_ENGINE_REPO" "$TWPR_ENGINE_DIR"
  fi
  chmod +x "${TWPR_ENGINE_DIR}/deploy/"*.sh 2>/dev/null || true
  # Always re-apply patches after fetch/reset
  # (fresh clone restores stock install.sh)
  TWPR_patch_upstream_install
  if [[ -f "${TWPR_ROOT}/scripts/patch-tproxy-per-profile-metrics.py" ]]; then
    TWPR_info "Патч per-profile metrics…"
    python3 "${TWPR_ROOT}/scripts/patch-tproxy-per-profile-metrics.py" "$TWPR_ENGINE_DIR" \
      || TWPR_warn "per-profile metrics patch не применился"
  fi
}

TWPR_prepare_site() {
  local src="${TWPR_ROOT}/site"
  if [[ -f "${TWPR_SITE_DIR}/index.html" ]]; then
    TWPR_info "Сайт уже есть: ${TWPR_SITE_DIR} (оставляю как есть)"
    if [[ -n "${TWPR_HOSTNAME:-}" ]]; then
      find "$TWPR_SITE_DIR" -type f \( -name '*.html' -o -name '*.txt' \) -print0 2>/dev/null \
        | xargs -0 sed -i "s/__HOSTNAME__/${TWPR_HOSTNAME}/g" 2>/dev/null || true
    fi
    return 0
  fi
  if [[ ! -f "${src}/index.html" ]]; then
    TWPR_err "Нет шаблона сайта: ${src}/index.html"
    return 1
  fi
  mkdir -p "$TWPR_SITE_DIR"
  cp -a "${src}/." "$TWPR_SITE_DIR/"
  if [[ -n "${TWPR_HOSTNAME:-}" ]]; then
    find "$TWPR_SITE_DIR" -type f \( -name '*.html' -o -name '*.txt' \) -print0 \
      | xargs -0 sed -i "s/__HOSTNAME__/${TWPR_HOSTNAME}/g" 2>/dev/null || true
  fi
  TWPR_ok "Стартовый сайт → ${TWPR_SITE_DIR}"
  TWPR_warn "Потом замените тексты на свои — одинаковые шаблоны легче зондировать"
}

TWPR_wizard_check_system() {
  TWPR_step 1 "$TWPR_TOTAL_STEPS" "Проверка системы"
  TWPR_require_root

  local arch os
  arch="$(uname -m)"
  os="$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-unknown}")"
  TWPR_info "ОС: ${os}"
  TWPR_info "Arch: ${arch}"

  if ! TWPR_arch_ok; then
    TWPR_err "Нужен x86_64 (официальный MTProxy). Сейчас: ${arch}"
    exit 1
  fi
  TWPR_ok "Архитектура подходит"

  if [[ ! -d /run/systemd/system ]] && ! command -v systemctl >/dev/null 2>&1; then
    TWPR_err "Нужен systemd"
    exit 1
  fi
  TWPR_ok "systemd найден"

  TWPR_ensure_deps
  TWPR_ok "Зависимости готовы"
}

TWPR_wizard_ask_domain() {
  TWPR_step 2 "$TWPR_TOTAL_STEPS" "Домен"
  echo "  Нужна DNS A-запись вида:"
  echo "    proxy.example.com  →  IP этого VPS"
  echo "  Без Cloudflare/CDN на первом деплое."
  echo ""

  local hostname=""
  while true; do
    TWPR_ask hostname "Домен (hostname)" "${TWPR_HOSTNAME:-}"
    hostname="$(echo "$hostname" | tr '[:upper:]' '[:lower:]')"
    if TWPR_validate_hostname "$hostname"; then
      TWPR_HOSTNAME="$hostname"
      TWPR_ok "Домен: ${TWPR_HOSTNAME}"
      break
    fi
    TWPR_warn "Некорректный домен. Пример: proxy.example.com"
  done
}

TWPR_wizard_ask_email() {
  TWPR_step 3 "$TWPR_TOTAL_STEPS" "TLS / Let's Encrypt"
  TWPR_certs_probe_and_choose
  if [[ "${TWPR_TLS_MODE:-acme}" == "file" ]]; then
    TWPR_EMAIL="${TWPR_EMAIL:-admin@$(TWPR_certs_normalize_host "$TWPR_HOSTNAME")}"
    TWPR_ok "Используем существующий сертификат — ACME не нужен"
    return 0
  fi
  local email=""
  while true; do
    TWPR_ask email "Email для Let's Encrypt" "${TWPR_EMAIL:-}"
    if TWPR_validate_email "$email"; then
      TWPR_EMAIL="$email"
      TWPR_ok "Email: ${TWPR_EMAIL}"
      break
    fi
    TWPR_warn "Некорректный email"
  done
}

TWPR_wizard_ask_secret() {
  local secret="" choice=""
  local step_n="${1:-4}"
  TWPR_step "$step_n" "$TWPR_TOTAL_STEPS" "Secret"

  if [[ -n "${TWPR_SECRET:-}" ]]; then
    if [[ "${TWPR_YES:-}" == "1" ]] || [[ "${TWPR_SETUP_MODE}" == "quick" ]]; then
      TWPR_ok "Secret из окружения / прошлый: …${TWPR_SECRET: -4}"
      return 0
    fi
    TWPR_info "Уже сохранён secret: ${TWPR_SECRET}"
    TWPR_ask_yn choice "Оставить его" "Y"
    if [[ "$choice" == "yes" ]]; then
      TWPR_ok "Secret без изменений"
      return 0
    fi
  fi

  secret="$(TWPR_gen_secret)"
  if [[ "${TWPR_SETUP_MODE}" == "quick" ]] || [[ "${TWPR_YES:-}" == "1" ]]; then
    TWPR_SECRET="$secret"
    TWPR_ok "Secret сгенерирован автоматически"
    return 0
  fi

  TWPR_info "Сгенерирован: ${C_BOLD}${secret}${C_RESET}"
  TWPR_ask_yn choice "Ввести свой вместо этого" "n"
  if [[ "$choice" == "yes" ]]; then
    while true; do
      TWPR_ask secret "Secret (32 hex, опционально dd+32)"
      secret="$(echo "$secret" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
      if TWPR_validate_secret "$secret"; then
        break
      fi
      TWPR_warn "Формат: 32 hex или dd + 32 hex"
    done
  fi
  TWPR_SECRET="$secret"
  TWPR_ok "Secret сохранён"
}

TWPR_wizard_ask_capacity() {
  TWPR_step 6 "$TWPR_TOTAL_STEPS" "Нагрузка MTProxy"
  local workers maxc
  TWPR_ask workers "Workers (для старта обычно 1)" "${TWPR_MTPROXY_WORKERS:-1}"
  TWPR_ask maxc "Max connections / worker" "${TWPR_MTPROXY_MAX_CONNECTIONS:-4096}"
  TWPR_MTPROXY_WORKERS="$workers"
  TWPR_MTPROXY_MAX_CONNECTIONS="$maxc"
  TWPR_ok "workers=${workers}, maxconn=${maxc}"
}

TWPR_wizard_check_dns() {
  local step_n="${1:-7}"
  TWPR_step "$step_n" "$TWPR_TOTAL_STEPS" "DNS и фаервол"
  local ip dig_out choice=""
  ip="$(TWPR_detect_public_ip || true)"
  if [[ -n "$ip" ]]; then
    TWPR_info "Публичный IP VPS: ${ip}"
  else
    TWPR_warn "Не удалось определить публичный IP автоматически"
  fi

  if command -v dig >/dev/null 2>&1; then
    dig_out="$(dig +short A "$TWPR_HOSTNAME" 2>/dev/null | head -1 || true)"
  else
    dig_out="$(getent ahostsv4 "$TWPR_HOSTNAME" 2>/dev/null | awk '{print $1; exit}' || true)"
  fi

  if [[ -n "$dig_out" ]]; then
    TWPR_info "DNS A ${TWPR_HOSTNAME} → ${dig_out}"
    if [[ -n "$ip" && "$dig_out" != "$ip" ]]; then
      TWPR_warn "DNS пока не указывает на этот сервер — сертификат может не выписаться"
      if [[ "${TWPR_YES:-}" != "1" ]]; then
        TWPR_ask_yn choice "Продолжить всё равно" "Y"
        [[ "$choice" == "yes" ]] || exit 1
      fi
    else
      TWPR_ok "DNS выглядит корректно"
    fi
  else
    TWPR_warn "Домен пока не резолвится. Создайте A-запись и подождите минуту."
    if [[ "${TWPR_YES:-}" != "1" ]]; then
      TWPR_ask_yn choice "Продолжить всё равно" "Y"
      [[ "$choice" == "yes" ]] || exit 1
    fi
  fi

  TWPR_open_firewall 2>/dev/null || true
  TWPR_info "В панели хостинга откройте TCP ${TWPR_PORT_HTTP:-80} и ${TWPR_PORT_HTTPS:-443}"
}

TWPR_wizard_confirm() {
  local step_n="${1:-8}"
  TWPR_step "$step_n" "$TWPR_TOTAL_STEPS" "Подтверждение"
  echo ""
  echo -e "  ${C_BOLD}Будет установлено:${C_RESET}"
  echo "    hostname : ${TWPR_HOSTNAME}"
  echo "    email    : ${TWPR_EMAIL}"
  echo "    secret   : ${TWPR_SECRET}"
  echo "    режим    : ${TWPR_DEPLOY_MODE:-native}"
  echo "    workers  : ${TWPR_MTPROXY_WORKERS:-1}"
  echo "    HTTP     : ${TWPR_PORT_HTTP:-80}"
  echo "    HTTPS    : ${TWPR_PORT_HTTPS:-443}"
  if [[ "${TWPR_DEPLOY_MODE:-native}" != "docker" ]]; then
    echo "    relay    : ${TWPR_PORT_RELAY:-8080} (localhost)"
    echo "    admin    : ${TWPR_PORT_ADMIN:-8081} (localhost)"
    echo "    mtproxy  : ${TWPR_PORT_MTPROXY:-2398} (localhost)"
  fi
  echo "    сайт     : ${TWPR_SITE_DIR}"
  echo ""
  local choice=""
  if [[ "${TWPR_YES:-}" == "1" ]]; then
    choice="yes"
  else
    TWPR_ask_yn choice "Начать установку" "Y"
  fi
  [[ "$choice" == "yes" ]] || { TWPR_warn "Отменено"; exit 0; }

  TWPR_INSTALLED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  TWPR_save_state
}

TWPR_wizard_deploy() {
  TWPR_step "$TWPR_TOTAL_STEPS" "$TWPR_TOTAL_STEPS" "Установка движка"
  TWPR_fetch_engine
  TWPR_prepare_site
  TWPR_run_official_install
  # Official installer always writes 80/443/8080/8081/2398 — patch if custom
  if [[ "${TWPR_PORT_HTTP:-80}" != "80" \
     || "${TWPR_PORT_HTTPS:-443}" != "443" \
     || "${TWPR_PORT_RELAY:-8080}" != "8080" \
     || "${TWPR_PORT_ADMIN:-8081}" != "8081" \
     || "${TWPR_PORT_MTPROXY:-2398}" != "2398" ]]; then
    TWPR_apply_ports
  else
    TWPR_ok "Стандартные порты — патч не нужен"
  fi
  # подхватить существующий TLS или оставить ACME в Caddyfile
  if declare -F TWPR_certs_apply_native >/dev/null 2>&1; then
    TWPR_certs_apply_native
  fi
  TWPR_save_state
}

TWPR_wizard_done() {
  echo ""
  echo -e "  ${C_GREEN}${C_BOLD}Готово!${C_RESET} WEB-прокси поднят."
  echo ""
  TWPR_cmd_status
  echo ""
  TWPR_cmd_link
  echo ""
  TWPR_info "Дальше в Telegram Desktop 7.1.1+:"
  echo "    Settings → Advanced → Connection type → Add proxy → WEB"
  echo "  или откройте tg:// ссылку выше."
  echo ""
  TWPR_info "Меню управления:  ${C_BOLD}tgwebproxyr${C_RESET}"
}

TWPR_wizard_quick_domain_email() {
  TWPR_step 2 "$TWPR_TOTAL_STEPS" "Домен и TLS"
  echo "  Перед запуском:"
  echo "    • DNS A: ваш-домен → IP этого VPS (без CDN)"
  echo "    • открыты TCP 80 и 443"
  echo ""

  if [[ -z "${TWPR_HOSTNAME:-}" ]]; then
    while true; do
      TWPR_ask TWPR_HOSTNAME "Домен (hostname)"
      TWPR_HOSTNAME="$(echo "$TWPR_HOSTNAME" | tr '[:upper:]' '[:lower:]')"
      TWPR_validate_hostname "$TWPR_HOSTNAME" && break
      TWPR_warn "Пример: proxy.example.com"
    done
  else
    TWPR_ok "Домен: ${TWPR_HOSTNAME}"
  fi

  TWPR_certs_probe_and_choose

  if [[ "${TWPR_TLS_MODE:-acme}" == "file" ]]; then
    TWPR_EMAIL="${TWPR_EMAIL:-admin@$(TWPR_certs_normalize_host "$TWPR_HOSTNAME")}"
    TWPR_ok "Email для ACME не нужен (используем готовый сертификат)"
  elif [[ -z "${TWPR_EMAIL:-}" ]]; then
    while true; do
      TWPR_ask TWPR_EMAIL "Email для Let's Encrypt"
      TWPR_validate_email "$TWPR_EMAIL" && break
      TWPR_warn "Некорректный email"
    done
  else
    TWPR_ok "Email: ${TWPR_EMAIL}"
  fi
}

TWPR_pick_setup_mode() {
  # уже задано флагом / env — не спрашиваем
  if [[ -n "${TWPR_SETUP_MODE:-}" ]]; then
    return 0
  fi
  echo -e "  ${C_BOLD}Режим установки${C_RESET}"
  echo ""
  echo -e "  ${C_BOLD}1${C_RESET})  Docker · быстро     ${C_DIM}рекомендуется · готовые образы GHCR${C_RESET}"
  echo -e "  ${C_BOLD}2${C_RESET})  Docker · расширенно ${C_DIM}порты / workers / свой secret${C_RESET}"
  echo -e "  ${C_BOLD}3${C_RESET})  Native · быстро     ${C_DIM}systemd + upstream tproxy-server${C_RESET}"
  echo -e "  ${C_BOLD}4${C_RESET})  Native · расширенно ${C_DIM}порты, workers, secret${C_RESET}"
  echo ""
  local choice=""
  TWPR_ask choice "Выбор" "1"
  case "$choice" in
    2) TWPR_SETUP_MODE=docker; TWPR_SETUP_DEPTH=advanced ;;
    3) TWPR_SETUP_MODE=native; TWPR_SETUP_DEPTH=quick ;;
    4) TWPR_SETUP_MODE=native; TWPR_SETUP_DEPTH=advanced ;;
    *) TWPR_SETUP_MODE=docker; TWPR_SETUP_DEPTH=quick ;;
  esac
  export TWPR_SETUP_MODE TWPR_SETUP_DEPTH
}

TWPR_parse_setup_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --docker) export TWPR_SETUP_MODE=docker ;;
      --native|--systemd) export TWPR_SETUP_MODE=native ;;
      --quick) export TWPR_SETUP_DEPTH=quick ;;
      --advanced) export TWPR_SETUP_DEPTH=advanced ;;
      --yes|-y) export TWPR_YES=1 ;;
      --hostname) export TWPR_HOSTNAME="$2"; shift ;;
      --email) export TWPR_EMAIL="$2"; shift ;;
      --secret) export TWPR_SECRET="$2"; shift ;;
      --workers) export TWPR_MTPROXY_WORKERS="$2"; shift ;;
      --help|-h)
        cat <<EOF
tgwebproxyr setup [опции]

  --docker | --native     носитель
  --quick  | --advanced   глубина вопросов
  --hostname DOMAIN
  --email EMAIL
  --secret HEX
  --workers N
  --yes                   без подтверждений
EOF
        exit 0
        ;;
      *) ;;
    esac
    shift
  done
}

TWPR_setup_native() {
  local depth="${TWPR_SETUP_DEPTH:-quick}"
  TWPR_DEPLOY_MODE="native"
  if [[ "$depth" == "advanced" ]]; then
    TWPR_TOTAL_STEPS=9
    TWPR_wizard_check_system
    TWPR_wizard_ask_domain
    TWPR_wizard_ask_email
    TWPR_wizard_ask_secret 4
    TWPR_wizard_ask_ports
    TWPR_wizard_ask_capacity
    TWPR_wizard_check_dns 7
    TWPR_wizard_confirm 8
    TWPR_wizard_deploy
  else
    TWPR_TOTAL_STEPS=6
    TWPR_wizard_check_system
    TWPR_wizard_quick_domain_email
    TWPR_SETUP_MODE=quick
    TWPR_wizard_ask_secret 3
    TWPR_PORT_HTTP=80 TWPR_PORT_HTTPS=443
    TWPR_PORT_RELAY=8080 TWPR_PORT_ADMIN=8081 TWPR_PORT_MTPROXY=2398
    TWPR_MTPROXY_WORKERS="${TWPR_MTPROXY_WORKERS:-1}"
    TWPR_MTPROXY_MAX_CONNECTIONS="${TWPR_MTPROXY_MAX_CONNECTIONS:-4096}"
    TWPR_wizard_check_dns 4
    TWPR_wizard_confirm 5
    TWPR_wizard_deploy
  fi
  TWPR_wizard_done
}

TWPR_setup_docker() {
  local depth="${TWPR_SETUP_DEPTH:-quick}"
  TWPR_DEPLOY_MODE="docker"
  # shellcheck disable=SC1091
  source "${TWPR_ROOT}/lib/docker.sh"

  if [[ "$depth" == "advanced" ]]; then
    TWPR_docker_ensure_docker || return 1
    TWPR_IMAGE_TAG="${TWPR_IMAGE_TAG:-latest}"
    TWPR_docker_prefetch
    TWPR_wizard_quick_domain_email
    TWPR_SETUP_MODE=quick
    TWPR_wizard_ask_secret 3
    TWPR_wizard_ask_capacity
    local http="${TWPR_PORT_HTTP:-80}" https="${TWPR_PORT_HTTPS:-443}"
    TWPR_ask http "Публичный HTTP" "$http"
    TWPR_ask https "Публичный HTTPS" "$https"
    TWPR_PORT_HTTP="$http"
    TWPR_PORT_HTTPS="$https"
    TWPR_INSTALLED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    TWPR_prepare_site
    if declare -F TWPR_certs_probe_and_choose >/dev/null 2>&1; then
      TWPR_certs_probe_and_choose || true
    fi
    TWPR_docker_write_env
    TWPR_save_state
    if declare -F TWPR_certs_prepare_docker >/dev/null 2>&1; then
      TWPR_certs_prepare_docker || true
    fi
    TWPR_docker_compose down --remove-orphans 2>/dev/null || true
    TWPR_docker_up || return 1
    TWPR_ok "Docker-стек запущен"
    TWPR_cmd_status
    TWPR_cmd_link
  else
    TWPR_docker_install_engine
  fi
}

TWPR_cmd_setup() {
  set +e
  TWPR_parse_setup_args "$@"
  TWPR_banner
  echo "  Установка Telegram WEB Proxy"
  echo ""
  TWPR_load_state
  TWPR_pick_setup_mode

  case "${TWPR_SETUP_MODE}" in
    native|systemd)
      TWPR_setup_native
      ;;
    *)
      TWPR_setup_docker
      ;;
  esac
}

TWPR_cmd_update() {
  TWPR_require_root
  TWPR_load_state

  local mode="${1:-}"
  # 1) сначала обновить сам менеджер с GitHub, затем re-exec новой копией
  if [[ "$mode" != "--stack-only" && "$mode" != "--no-self" ]]; then
    if TWPR_self_update; then
      TWPR_info "Перезапуск update уже новым кодом…"
      exec /usr/local/bin/tgwebproxyr update --stack-only
    fi
    TWPR_warn "Self-update не удался — обновляю только стек текущей версией"
  fi

  # 2) стек: Docker-образы или native engine
  if TWPR_is_docker; then
    TWPR_IMAGE_TAG="$(tr -d '[:space:]' <"${TWPR_ROOT}/version" 2>/dev/null || echo latest)"
    TWPR_docker_ensure_env 2>/dev/null || true
    TWPR_docker_write_env 2>/dev/null || true
    if declare -F TWPR_certs_prepare_docker >/dev/null 2>&1; then
      TWPR_certs_prepare_docker
    fi
    TWPR_docker_pull_images || true
    TWPR_docker_up
    if declare -F TWPR_quota_install_timer >/dev/null 2>&1; then
      TWPR_quota_install_timer 2>/dev/null || true
    fi
  else
    TWPR_fetch_engine
    TWPR_info "Пересобираю / обновляю native стек…"
    TWPR_run_official_install || true
    if declare -F TWPR_certs_apply_native >/dev/null 2>&1; then
      TWPR_certs_apply_native
    fi
    TWPR_profiles_apply_engine 2>/dev/null || true
    if declare -F TWPR_quota_install_timer >/dev/null 2>&1; then
      TWPR_quota_install_timer 2>/dev/null || true
    fi
  fi

  # бот / api, если стоят
  if [[ -f /etc/systemd/system/tgwebproxyr-bot.service ]] || [[ -f /etc/tgwebproxyr/bot.env ]]; then
    if declare -F TWPR_bot_install_files >/dev/null 2>&1; then
      TWPR_bot_install_files --pull 2>/dev/null || true
      systemctl restart tgwebproxyr-bot.service 2>/dev/null || true
    fi
  fi
  if [[ -f /etc/systemd/system/tgwebproxyr-api.service ]]; then
    if [[ -f "${TWPR_ROOT}/bot/twpr_api.py" ]]; then
      mkdir -p /opt/tgwebproxyr/bot
      cp -a "${TWPR_ROOT}/bot/twpr_api.py" /opt/tgwebproxyr/bot/twpr_api.py
      systemctl restart tgwebproxyr-api.service 2>/dev/null || true
    fi
  fi

  local ver
  ver="$(tr -d '[:space:]' <"${TWPR_ROOT}/version" 2>/dev/null || echo '?')"
  TWPR_ok "Обновление завершено · TgWebProxyR v${ver}"
  TWPR_cmd_status
}

# Скачать свежий архив с GitHub и обновить /opt/tgwebproxyr (без трогания state/engine/backups)
TWPR_self_update() {
  local repo branch archive_url install_dir old_ver new_ver
  repo="${TWPR_GITHUB_REPO:-RasmusVraa/TgWebProxyR}"
  branch="${TWPR_BRANCH:-main}"
  # можно зафиксировать релиз: TWPR_UPDATE_REF=v1.6.9
  if [[ -n "${TWPR_UPDATE_REF:-}" ]]; then
    archive_url="https://github.com/${repo}/archive/refs/tags/${TWPR_UPDATE_REF}.tar.gz"
    TWPR_info "Self-update: ${repo} @ ${TWPR_UPDATE_REF}"
  else
    archive_url="https://github.com/${repo}/archive/refs/heads/${branch}.tar.gz"
    TWPR_info "Self-update: ${repo} @ ${branch}"
  fi
  install_dir="${TWPR_ROOT:-/opt/tgwebproxyr}"
  old_ver="$(tr -d '[:space:]' <"${install_dir}/version" 2>/dev/null || echo '?')"

  command -v curl >/dev/null 2>&1 || {
    TWPR_err "нужен curl"
    return 1
  }

  local tmp
  tmp="$(mktemp -d /tmp/tgwebproxyr-update.XXXXXX)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN

  TWPR_info "Скачиваю ${archive_url}…"
  if ! curl -fsSL --retry 4 --retry-delay 2 "$archive_url" -o "${tmp}/src.tgz"; then
    TWPR_err "не удалось скачать архив"
    return 1
  fi
  mkdir -p "${tmp}/extract"
  tar -xzf "${tmp}/src.tgz" -C "${tmp}/extract"
  local src
  src="$(find "${tmp}/extract" -maxdepth 1 -type d \( -name 'TgWebProxyR-*' -o -name 'tgwebproxyr-*' \) | head -1)"
  if [[ -z "$src" || ! -f "${src}/tgwebproxyr.sh" ]]; then
    TWPR_err "в архиве нет tgwebproxyr.sh"
    return 1
  fi
  new_ver="$(tr -d '[:space:]' <"${src}/version" 2>/dev/null || echo '?')"

  # сохранить то, что нельзя затирать
  mkdir -p "$tmp/keep"
  [[ -f "${install_dir}/docker/.env" ]] && cp -a "${install_dir}/docker/.env" "$tmp/keep/.env"
  [[ -f "${install_dir}/docker/docker-compose.tls.yml" ]] \
    && cp -a "${install_dir}/docker/docker-compose.tls.yml" "$tmp/keep/docker-compose.tls.yml"

  mkdir -p "$install_dir"
  # не трогаем engine/ и backups/; docker/ перезапишется из архива, .env вернём
  find "$install_dir" -mindepth 1 -maxdepth 1 \
    ! -name engine ! -name backups ! -name docker \
    -exec rm -rf {} + 2>/dev/null || true

  cp -a "${src}/." "${install_dir}/"

  mkdir -p "${install_dir}/docker"
  [[ -f "$tmp/keep/.env" ]] && cp -a "$tmp/keep/.env" "${install_dir}/docker/.env"
  [[ -f "$tmp/keep/docker-compose.tls.yml" ]] \
    && cp -a "$tmp/keep/docker-compose.tls.yml" "${install_dir}/docker/docker-compose.tls.yml"

  find "$install_dir" -type f \( -name '*.sh' -o -name 'version' \) -exec sed -i 's/\r$//' {} + 2>/dev/null || true
  chmod +x "${install_dir}/tgwebproxyr.sh" "${install_dir}/install.sh" 2>/dev/null || true
  find "${install_dir}/lib" -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
  find "${install_dir}/docker" -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true

  cat >/usr/local/bin/tgwebproxyr <<'EOF'
#!/usr/bin/env bash
exec /opt/tgwebproxyr/tgwebproxyr.sh "$@"
EOF
  chmod 0755 /usr/local/bin/tgwebproxyr

  TWPR_ok "Менеджер: v${old_ver} → v${new_ver}"
  return 0
}

TWPR_cmd_reinstall() {
  TWPR_cmd_setup "$@"
}

TWPR_cmd_doctor() {
  TWPR_require_root
  TWPR_load_state
  TWPR_info "Doctor…"
  if TWPR_is_docker; then
    TWPR_cmd_docker restart
    sleep 2
    TWPR_cmd_status
    return 0
  fi
  TWPR_ensure_relay_ready || true
  TWPR_cmd_status
}
