#!/usr/bin/env bash
# TgWebProxyR — engine fetch + deploy wrapper around tproxy-server

TWPR_fetch_engine() {
  TWPR_ensure_deps
  mkdir -p "$(dirname "$TWPR_ENGINE_DIR")"
  if [[ -d "${TWPR_ENGINE_DIR}/.git" ]]; then
    TWPR_info "Обновляю движок tproxy-server (${TWPR_ENGINE_REF})…"
    git -C "$TWPR_ENGINE_DIR" fetch --depth 1 origin "$TWPR_ENGINE_REF"
    git -C "$TWPR_ENGINE_DIR" checkout -q FETCH_HEAD || \
      git -C "$TWPR_ENGINE_DIR" checkout -q "$TWPR_ENGINE_REF"
    git -C "$TWPR_ENGINE_DIR" pull --ff-only origin "$TWPR_ENGINE_REF" 2>/dev/null || true
  else
    TWPR_info "Клонирую telegramdesktop/tproxy-server…"
    rm -rf "$TWPR_ENGINE_DIR"
    git clone --depth 1 --branch "$TWPR_ENGINE_REF" "$TWPR_ENGINE_REPO" "$TWPR_ENGINE_DIR"
  fi
  [[ -x "${TWPR_ENGINE_DIR}/deploy/install.sh" ]] || chmod +x "${TWPR_ENGINE_DIR}/deploy/"*.sh
}

TWPR_prepare_site() {
  local src="${TWPR_ROOT}/site"
  if [[ -f "${TWPR_SITE_DIR}/index.html" ]]; then
    TWPR_info "Публичный сайт уже есть: ${TWPR_SITE_DIR} (не перезаписываю)"
    return 0
  fi
  if [[ ! -f "${src}/index.html" ]]; then
    TWPR_err "Нет шаблона сайта в ${src}"
    return 1
  fi
  mkdir -p "$TWPR_SITE_DIR"
  cp -a "${src}/." "$TWPR_SITE_DIR/"
  # Подставить hostname в шаблон, если задан
  if [[ -n "${TWPR_HOSTNAME:-}" ]]; then
    find "$TWPR_SITE_DIR" -type f \( -name '*.html' -o -name '*.txt' \) -print0 \
      | xargs -0 sed -i "s/__HOSTNAME__/${TWPR_HOSTNAME}/g" 2>/dev/null || true
  fi
  TWPR_ok "Стартовый сайт скопирован в ${TWPR_SITE_DIR}"
  TWPR_warn "Замените тексты/стиль на свои — одинаковые шаблоны легче зондировать."
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
  TWPR_info "Запускаю официальный deploy/install.sh…"
  TWPR_log "official install hostname=${TWPR_HOSTNAME}"
  (
    cd "$TWPR_ENGINE_DIR"
    bash ./deploy/install.sh "${args[@]}"
  )
}

TWPR_cmd_setup() {
  TWPR_require_root
  TWPR_banner

  if ! TWPR_arch_ok; then
    TWPR_err "Официальный MTProxy требует x86_64. Текущая архитектура: $(uname -m)"
    exit 1
  fi

  TWPR_load_state
  TWPR_sec "Мастер установки WEB-прокси"

  local hostname email secret workers maxc ip dig_out
  hostname="$(TWPR_prompt "Домен (A-запись на этот сервер)" "${TWPR_HOSTNAME:-}")"
  email="$(TWPR_prompt "Email для Let's Encrypt" "${TWPR_EMAIL:-}")"

  if [[ -z "${TWPR_SECRET:-}" ]]; then
    secret="$(TWPR_gen_secret)"
    TWPR_info "Сгенерирован secret: ${C_BOLD}${secret}${C_RESET}"
    if TWPR_confirm "Сгенерировать другой / ввести свой" "n"; then
      secret="$(TWPR_prompt "Secret (32 hex, опционально с dd)" "$secret")"
    fi
  else
    secret="$TWPR_SECRET"
    TWPR_info "Использую сохранённый secret"
  fi

  workers="$(TWPR_prompt "MTProxy workers" "${TWPR_MTPROXY_WORKERS:-1}")"
  maxc="$(TWPR_prompt "MTProxy max connections / worker" "${TWPR_MTPROXY_MAX_CONNECTIONS:-4096}")"

  hostname="$(echo "$hostname" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  secret="$(echo "$secret" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

  TWPR_validate_hostname "$hostname" || { TWPR_err "Некорректный hostname"; exit 2; }
  TWPR_validate_email "$email" || { TWPR_err "Некорректный email"; exit 2; }
  TWPR_validate_secret "$secret" || { TWPR_err "Secret: 32 hex или dd+32 hex"; exit 2; }

  TWPR_sec "Проверка DNS"
  ip="$(TWPR_detect_public_ip || true)"
  if command -v dig >/dev/null 2>&1; then
    dig_out="$(dig +short A "$hostname" | head -1 || true)"
  else
    dig_out="$(getent ahostsv4 "$hostname" 2>/dev/null | awk '{print $1; exit}' || true)"
  fi
  if [[ -n "$ip" ]]; then
    TWPR_info "Публичный IP сервера: ${ip}"
  fi
  if [[ -n "$dig_out" ]]; then
    TWPR_info "DNS A ${hostname} → ${dig_out}"
    if [[ -n "$ip" && "$dig_out" != "$ip" ]]; then
      TWPR_warn "DNS пока не совпадает с IP сервера. ACME может не пройти."
      TWPR_confirm "Продолжить всё равно" "Y" || exit 1
    fi
  else
    TWPR_warn "Не удалось резолвить ${hostname}. Убедитесь, что A-запись готова."
    TWPR_confirm "Продолжить" "Y" || exit 1
  fi

  echo ""
  TWPR_info "Hostname : ${hostname}"
  TWPR_info "Email    : ${email}"
  TWPR_info "Workers  : ${workers}"
  TWPR_info "Порты    : 80/443 публично; 2398/8080/8081 только localhost"
  TWPR_confirm "Начать установку" "Y" || exit 0

  TWPR_HOSTNAME="$hostname"
  TWPR_EMAIL="$email"
  TWPR_SECRET="$secret"
  TWPR_MTPROXY_WORKERS="$workers"
  TWPR_MTPROXY_MAX_CONNECTIONS="$maxc"
  TWPR_INSTALLED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  TWPR_save_state

  TWPR_fetch_engine
  TWPR_prepare_site
  TWPR_run_official_install

  TWPR_ok "Установка завершена"
  TWPR_cmd_status
  echo ""
  TWPR_cmd_link
}

TWPR_cmd_update() {
  TWPR_require_root
  TWPR_load_state
  TWPR_fetch_engine
  if [[ -x "${TWPR_ENGINE_DIR}/deploy/update-relay.sh" ]]; then
    TWPR_info "Обновляю только relay (update-relay.sh)…"
    bash "${TWPR_ENGINE_DIR}/deploy/update-relay.sh"
  else
    TWPR_err "update-relay.sh не найден"
    return 1
  fi
  TWPR_ok "Relay обновлён"
  TWPR_cmd_status
}

TWPR_cmd_reinstall() {
  TWPR_require_root
  TWPR_load_state
  [[ -n "${TWPR_HOSTNAME:-}" && -n "${TWPR_EMAIL:-}" && -n "${TWPR_SECRET:-}" ]] || {
    TWPR_err "Нет сохранённых настроек. Сначала: tgwebproxyr setup"
    return 1
  }
  TWPR_warn "Повторный install заменит Caddyfile и single-profile конфиг."
  TWPR_confirm "Продолжить" "n" || return 0
  TWPR_fetch_engine
  TWPR_prepare_site
  TWPR_run_official_install
  TWPR_cmd_link
}
