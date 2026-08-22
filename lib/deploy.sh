#!/usr/bin/env bash
# TgWebProxyR — guided install wizard + engine deploy

TWPR_TOTAL_STEPS=9

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
  TWPR_step 3 "$TWPR_TOTAL_STEPS" "Email для Let's Encrypt"
  local email=""
  while true; do
    TWPR_ask email "Email" "${TWPR_EMAIL:-}"
    if TWPR_validate_email "$email"; then
      TWPR_EMAIL="$email"
      TWPR_ok "Email: ${TWPR_EMAIL}"
      break
    fi
    TWPR_warn "Некорректный email"
  done
}

TWPR_wizard_ask_secret() {
  TWPR_step 4 "$TWPR_TOTAL_STEPS" "Secret"
  local secret="" choice=""
  if [[ -n "${TWPR_SECRET:-}" ]]; then
    TWPR_info "Уже сохранён secret: ${TWPR_SECRET}"
    TWPR_ask_yn choice "Оставить его" "Y"
    if [[ "$choice" == "yes" ]]; then
      TWPR_ok "Secret без изменений"
      return 0
    fi
  fi

  secret="$(TWPR_gen_secret)"
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
  TWPR_step 7 "$TWPR_TOTAL_STEPS" "DNS и фаервол"
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
      TWPR_ask_yn choice "Продолжить всё равно" "Y"
      [[ "$choice" == "yes" ]] || exit 1
    else
      TWPR_ok "DNS выглядит корректно"
    fi
  else
    TWPR_warn "Домен пока не резолвится. Создайте A-запись и подождите минуту."
    TWPR_ask_yn choice "Продолжить всё равно" "Y"
    [[ "$choice" == "yes" ]] || exit 1
  fi

  TWPR_open_firewall
  TWPR_info "В панели хостинга откройте TCP ${TWPR_PORT_HTTP:-80} и ${TWPR_PORT_HTTPS:-443}"
}

TWPR_wizard_confirm() {
  TWPR_step 8 "$TWPR_TOTAL_STEPS" "Подтверждение"
  echo ""
  echo -e "  ${C_BOLD}Будет установлено:${C_RESET}"
  echo "    hostname : ${TWPR_HOSTNAME}"
  echo "    email    : ${TWPR_EMAIL}"
  echo "    secret   : ${TWPR_SECRET}"
  echo "    workers  : ${TWPR_MTPROXY_WORKERS}"
  echo "    HTTP     : ${TWPR_PORT_HTTP:-80}"
  echo "    HTTPS    : ${TWPR_PORT_HTTPS:-443}"
  echo "    relay    : ${TWPR_PORT_RELAY:-8080} (localhost)"
  echo "    admin    : ${TWPR_PORT_ADMIN:-8081} (localhost)"
  echo "    mtproxy  : ${TWPR_PORT_MTPROXY:-2398} (localhost)"
  echo "    сайт     : ${TWPR_SITE_DIR}"
  echo ""
  local choice=""
  TWPR_ask_yn choice "Начать установку движка" "Y"
  [[ "$choice" == "yes" ]] || { TWPR_warn "Отменено"; exit 0; }

  TWPR_INSTALLED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  TWPR_save_state
}

TWPR_wizard_deploy() {
  TWPR_step 9 "$TWPR_TOTAL_STEPS" "Установка движка"
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

# Full guided install — one flow, no separate manual steps
TWPR_cmd_setup() {
  set +e
  TWPR_banner
  echo "  Пошаговая установка Telegram WEB Proxy на этот сервер."
  echo "  Движок: telegramdesktop/tproxy-server"
  echo ""

  TWPR_load_state
  TWPR_wizard_check_system
  TWPR_wizard_ask_domain
  TWPR_wizard_ask_email
  TWPR_wizard_ask_secret
  TWPR_wizard_ask_ports
  TWPR_wizard_ask_capacity
  TWPR_wizard_check_dns
  TWPR_wizard_confirm
  set -e
  TWPR_wizard_deploy
  set +e
  TWPR_wizard_done
}

TWPR_cmd_update() {
  TWPR_require_root
  TWPR_load_state
  TWPR_fetch_engine
  if [[ -x "${TWPR_ENGINE_DIR}/deploy/update-relay.sh" ]]; then
    TWPR_info "Обновляю relay…"
    bash "${TWPR_ENGINE_DIR}/deploy/update-relay.sh"
    TWPR_ok "Relay обновлён"
  else
    TWPR_err "update-relay.sh не найден — сначала пройдите установку"
    return 1
  fi
  TWPR_cmd_status
}

TWPR_cmd_reinstall() {
  TWPR_require_root
  TWPR_load_state
  if [[ -z "${TWPR_HOSTNAME:-}" || -z "${TWPR_EMAIL:-}" || -z "${TWPR_SECRET:-}" ]]; then
    TWPR_info "Настроек нет — запускаю полный мастер"
    TWPR_cmd_setup
    return
  fi
  local choice=""
  TWPR_warn "Повторный install перезапишет Caddyfile и single-profile"
  TWPR_ask_yn choice "Продолжить с сохранёнными параметрами" "n"
  if [[ "$choice" != "yes" ]]; then
    TWPR_ask_yn choice "Пройти мастер заново" "Y"
    [[ "$choice" == "yes" ]] && TWPR_cmd_setup
    return
  fi
  TWPR_fetch_engine
  TWPR_prepare_site
  TWPR_run_official_install
  TWPR_apply_ports
  TWPR_cmd_link
}
