#!/usr/bin/env bash
# WebProxyL — engine fetch + deploy wrapper around tproxy-server

wpl_fetch_engine() {
  wpl_ensure_deps
  mkdir -p "$(dirname "$WPL_ENGINE_DIR")"
  if [[ -d "${WPL_ENGINE_DIR}/.git" ]]; then
    wpl_info "Обновляю движок tproxy-server (${WPL_ENGINE_REF})…"
    git -C "$WPL_ENGINE_DIR" fetch --depth 1 origin "$WPL_ENGINE_REF"
    git -C "$WPL_ENGINE_DIR" checkout -q FETCH_HEAD || \
      git -C "$WPL_ENGINE_DIR" checkout -q "$WPL_ENGINE_REF"
    git -C "$WPL_ENGINE_DIR" pull --ff-only origin "$WPL_ENGINE_REF" 2>/dev/null || true
  else
    wpl_info "Клонирую telegramdesktop/tproxy-server…"
    rm -rf "$WPL_ENGINE_DIR"
    git clone --depth 1 --branch "$WPL_ENGINE_REF" "$WPL_ENGINE_REPO" "$WPL_ENGINE_DIR"
  fi
  [[ -x "${WPL_ENGINE_DIR}/deploy/install.sh" ]] || chmod +x "${WPL_ENGINE_DIR}/deploy/"*.sh
}

wpl_prepare_site() {
  local src="${WPL_ROOT}/site"
  if [[ -f "${WPL_SITE_DIR}/index.html" ]]; then
    wpl_info "Публичный сайт уже есть: ${WPL_SITE_DIR} (не перезаписываю)"
    return 0
  fi
  if [[ ! -f "${src}/index.html" ]]; then
    wpl_err "Нет шаблона сайта в ${src}"
    return 1
  fi
  mkdir -p "$WPL_SITE_DIR"
  cp -a "${src}/." "$WPL_SITE_DIR/"
  # Подставить hostname в шаблон, если задан
  if [[ -n "${WPL_HOSTNAME:-}" ]]; then
    find "$WPL_SITE_DIR" -type f \( -name '*.html' -o -name '*.txt' \) -print0 \
      | xargs -0 sed -i "s/__HOSTNAME__/${WPL_HOSTNAME}/g" 2>/dev/null || true
  fi
  wpl_ok "Стартовый сайт скопирован в ${WPL_SITE_DIR}"
  wpl_warn "Замените тексты/стиль на свои — одинаковые шаблоны легче зондировать."
}

wpl_run_official_install() {
  local args=(
    --hostname "$WPL_HOSTNAME"
    --email "$WPL_EMAIL"
    --secret "$WPL_SECRET"
    --site-dir "$WPL_SITE_DIR"
    --mtproxy-workers "${WPL_MTPROXY_WORKERS:-1}"
    --mtproxy-max-connections "${WPL_MTPROXY_MAX_CONNECTIONS:-4096}"
  )
  wpl_info "Запускаю официальный deploy/install.sh…"
  wpl_log "official install hostname=${WPL_HOSTNAME}"
  (
    cd "$WPL_ENGINE_DIR"
    bash ./deploy/install.sh "${args[@]}"
  )
}

wpl_cmd_setup() {
  wpl_require_root
  wpl_banner

  if ! wpl_arch_ok; then
    wpl_err "Официальный MTProxy требует x86_64. Текущая архитектура: $(uname -m)"
    exit 1
  fi

  wpl_load_state
  wpl_sec "Мастер установки WEB-прокси"

  local hostname email secret workers maxc ip dig_out
  hostname="$(wpl_prompt "Домен (A-запись на этот сервер)" "${WPL_HOSTNAME:-}")"
  email="$(wpl_prompt "Email для Let's Encrypt" "${WPL_EMAIL:-}")"

  if [[ -z "${WPL_SECRET:-}" ]]; then
    secret="$(wpl_gen_secret)"
    wpl_info "Сгенерирован secret: ${C_BOLD}${secret}${C_RESET}"
    if wpl_confirm "Сгенерировать другой / ввести свой" "n"; then
      secret="$(wpl_prompt "Secret (32 hex, опционально с dd)" "$secret")"
    fi
  else
    secret="$WPL_SECRET"
    wpl_info "Использую сохранённый secret"
  fi

  workers="$(wpl_prompt "MTProxy workers" "${WPL_MTPROXY_WORKERS:-1}")"
  maxc="$(wpl_prompt "MTProxy max connections / worker" "${WPL_MTPROXY_MAX_CONNECTIONS:-4096}")"

  hostname="$(echo "$hostname" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  secret="$(echo "$secret" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

  wpl_validate_hostname "$hostname" || { wpl_err "Некорректный hostname"; exit 2; }
  wpl_validate_email "$email" || { wpl_err "Некорректный email"; exit 2; }
  wpl_validate_secret "$secret" || { wpl_err "Secret: 32 hex или dd+32 hex"; exit 2; }

  wpl_sec "Проверка DNS"
  ip="$(wpl_detect_public_ip || true)"
  if command -v dig >/dev/null 2>&1; then
    dig_out="$(dig +short A "$hostname" | head -1 || true)"
  else
    dig_out="$(getent ahostsv4 "$hostname" 2>/dev/null | awk '{print $1; exit}' || true)"
  fi
  if [[ -n "$ip" ]]; then
    wpl_info "Публичный IP сервера: ${ip}"
  fi
  if [[ -n "$dig_out" ]]; then
    wpl_info "DNS A ${hostname} → ${dig_out}"
    if [[ -n "$ip" && "$dig_out" != "$ip" ]]; then
      wpl_warn "DNS пока не совпадает с IP сервера. ACME может не пройти."
      wpl_confirm "Продолжить всё равно" "Y" || exit 1
    fi
  else
    wpl_warn "Не удалось резолвить ${hostname}. Убедитесь, что A-запись готова."
    wpl_confirm "Продолжить" "Y" || exit 1
  fi

  echo ""
  wpl_info "Hostname : ${hostname}"
  wpl_info "Email    : ${email}"
  wpl_info "Workers  : ${workers}"
  wpl_info "Порты    : 80/443 публично; 2398/8080/8081 только localhost"
  wpl_confirm "Начать установку" "Y" || exit 0

  WPL_HOSTNAME="$hostname"
  WPL_EMAIL="$email"
  WPL_SECRET="$secret"
  WPL_MTPROXY_WORKERS="$workers"
  WPL_MTPROXY_MAX_CONNECTIONS="$maxc"
  WPL_INSTALLED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  wpl_save_state

  wpl_fetch_engine
  wpl_prepare_site
  wpl_run_official_install

  wpl_ok "Установка завершена"
  wpl_cmd_status
  echo ""
  wpl_cmd_link
}

wpl_cmd_update() {
  wpl_require_root
  wpl_load_state
  wpl_fetch_engine
  if [[ -x "${WPL_ENGINE_DIR}/deploy/update-relay.sh" ]]; then
    wpl_info "Обновляю только relay (update-relay.sh)…"
    bash "${WPL_ENGINE_DIR}/deploy/update-relay.sh"
  else
    wpl_err "update-relay.sh не найден"
    return 1
  fi
  wpl_ok "Relay обновлён"
  wpl_cmd_status
}

wpl_cmd_reinstall() {
  wpl_require_root
  wpl_load_state
  [[ -n "${WPL_HOSTNAME:-}" && -n "${WPL_EMAIL:-}" && -n "${WPL_SECRET:-}" ]] || {
    wpl_err "Нет сохранённых настроек. Сначала: webproxyl setup"
    return 1
  }
  wpl_warn "Повторный install заменит Caddyfile и single-profile конфиг."
  wpl_confirm "Продолжить" "n" || return 0
  wpl_fetch_engine
  wpl_prepare_site
  wpl_run_official_install
  wpl_cmd_link
}
