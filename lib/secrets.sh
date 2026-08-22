#!/usr/bin/env bash
# TgWebProxyR — secret / profile helpers (Docker + Native)

TWPR_PROFILES_FILE="${TWPR_PROFILES_FILE:-/etc/tproxy-server/profiles.json}"

TWPR_profiles_path() {
  if TWPR_is_docker; then
    # в Docker профили внутри volume; основной secret — в .env / settings
    echo ""
    return 1
  fi
  [[ -f "$TWPR_PROFILES_FILE" ]] || return 1
  echo "$TWPR_PROFILES_FILE"
}

TWPR_cmd_secret_show() {
  TWPR_load_state
  if TWPR_is_docker; then
    TWPR_docker_ensure_env 2>/dev/null || true
  fi
  if [[ -z "${TWPR_SECRET:-}" ]]; then
    TWPR_err "Secret не сохранён"
    return 1
  fi
  echo "$TWPR_SECRET"
}

TWPR_cmd_secret_list() {
  TWPR_load_state
  echo -e "  ${C_BOLD}Secrets${C_RESET}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
  if TWPR_is_docker; then
    TWPR_docker_ensure_env 2>/dev/null || true
    if [[ -n "${TWPR_SECRET:-}" ]]; then
      TWPR_ok "default  …${TWPR_SECRET: -4}  ${C_DIM}(Docker · один shared secret)${C_RESET}"
    else
      TWPR_warn "пусто"
    fi
    return 0
  fi
  if [[ ! -f "$TWPR_PROFILES_FILE" ]] || ! command -v jq >/dev/null 2>&1; then
    if [[ -n "${TWPR_SECRET:-}" ]]; then
      TWPR_ok "default  …${TWPR_SECRET: -4}"
    else
      TWPR_warn "profiles.json нет — сначала setup"
    fi
    return 0
  fi
  jq -r '.profiles[]? | "  \(.name)\t…\(.secret[-4:])\t\(.backend // "-")"' \
    "$TWPR_PROFILES_FILE" 2>/dev/null || TWPR_warn "не удалось прочитать profiles"
}

TWPR_cmd_secret_link() {
  local name="${1:-}"
  TWPR_load_state
  if TWPR_is_docker; then
    TWPR_docker_ensure_env 2>/dev/null || true
  fi
  if [[ -z "$name" || "$name" == "default" ]]; then
    TWPR_cmd_link
    return
  fi
  if TWPR_is_docker; then
    TWPR_warn "В Docker один shared secret — используйте: tgwebproxyr link"
    TWPR_cmd_link
    return
  fi
  [[ -f "$TWPR_PROFILES_FILE" ]] || { TWPR_err "нет profiles.json"; return 1; }
  local secret
  secret="$(jq -r --arg n "$name" '.profiles[] | select(.name==$n) | .secret' "$TWPR_PROFILES_FILE" 2>/dev/null | head -1)"
  if [[ -z "$secret" || "$secret" == "null" ]]; then
    TWPR_err "Профиль не найден: ${name}"
    return 1
  fi
  echo ""
  echo -e "  ${C_BOLD}${name}${C_RESET}"
  echo "  $(TWPR_tg_link "${TWPR_HOSTNAME}" "$secret")"
  echo "  $(TWPR_web_link "${TWPR_HOSTNAME}" "$secret")"
}

TWPR_secret_apply_docker() {
  local new_secret="$1"
  TWPR_SECRET="$new_secret"
  TWPR_save_state
  TWPR_docker_write_env
  TWPR_info "Пересоздаю контейнеры с новым secret…"
  TWPR_docker_compose up -d --force-recreate --remove-orphans
}

TWPR_cmd_secret_rotate() {
  TWPR_require_root
  TWPR_load_state
  local new_secret choice="" name="${1:-}"
  new_secret="$(TWPR_gen_secret)"
  TWPR_info "Новый secret: ${C_BOLD}${new_secret}${C_RESET}"
  TWPR_ask_yn choice "Записать и перезапустить" "Y"
  [[ "$choice" == "yes" ]] || return 0

  if TWPR_is_docker; then
    TWPR_secret_apply_docker "$new_secret"
    TWPR_ok "Secret обновлён (Docker)"
    TWPR_cmd_link
    return 0
  fi

  if [[ ! -f "$TWPR_PROFILES_FILE" ]]; then
    TWPR_err "Не найден ${TWPR_PROFILES_FILE} — сначала setup"
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    TWPR_err "Нужен jq"
    return 1
  fi

  local tmp
  tmp="$(mktemp)"
  if [[ -n "$name" && "$name" != "default" ]]; then
    jq --arg n "$name" --arg s "$new_secret" '
      .profiles |= map(if .name == $n then .secret = $s else . end)
    ' "$TWPR_PROFILES_FILE" >"$tmp"
  else
    jq --arg s "$new_secret" '
      .profiles |= map(if .name == "default" or (. | length) == 1 then .secret = $s else . end)
      | if (.profiles | length) == 0 then
          {profiles:[{name:"default",secret:$s,backend:"127.0.0.1:2398",carrier_mode:"https"}]}
        else . end
    ' "$TWPR_PROFILES_FILE" >"$tmp"
    TWPR_SECRET="$new_secret"
    TWPR_save_state
  fi
  install -m 0400 "$tmp" "$TWPR_PROFILES_FILE"
  rm -f "$tmp"

  if [[ -z "$name" || "$name" == "default" ]] && [[ -f /etc/mtproxy/mtproxy.env ]]; then
    sed -i "s/^MTPROXY_SECRET=.*/MTPROXY_SECRET=${new_secret}/" /etc/mtproxy/mtproxy.env || true
  fi

  systemctl restart mtproxy tproxy-server 2>/dev/null || true
  TWPR_ok "Secret обновлён"
  TWPR_cmd_secret_link "${name:-default}"
}

TWPR_cmd_secret_add() {
  TWPR_require_root
  TWPR_load_state
  if TWPR_is_docker; then
    TWPR_err "В Docker сейчас один shared secret. Для нескольких профилей — native install."
    return 1
  fi
  local name secret backend
  name="${1:-}"
  [[ -n "$name" ]] || TWPR_ask name "Имя профиля" "user$(date +%s | tail -c 5)"
  secret="$(TWPR_gen_secret)"
  TWPR_ask backend "Backend loopback" "127.0.0.1:${TWPR_PORT_MTPROXY:-2398}"
  TWPR_info "Secret для ${name}: ${secret}"

  [[ -f "$TWPR_PROFILES_FILE" ]] || {
    TWPR_err "Сначала выполните setup"
    return 1
  }

  local tmp
  tmp="$(mktemp)"
  jq --arg n "$name" --arg s "$secret" --arg b "$backend" '
    .profiles += [{name:$n, secret:$s, backend:$b, carrier_mode:"https"}]
  ' "$TWPR_PROFILES_FILE" >"$tmp"
  install -m 0400 "$tmp" "$TWPR_PROFILES_FILE"
  rm -f "$tmp"
  systemctl restart tproxy-server
  TWPR_ok "Профиль ${name} добавлен"
  echo "  $(TWPR_tg_link "${TWPR_HOSTNAME}" "$secret")"
  echo "  $(TWPR_web_link "${TWPR_HOSTNAME}" "$secret")"
}

TWPR_cmd_secret_remove() {
  TWPR_require_root
  TWPR_load_state
  if TWPR_is_docker; then
    TWPR_err "В Docker один secret — используйте rotate, не remove"
    return 1
  fi
  local name="${1:-}" choice=""
  [[ -n "$name" ]] || TWPR_ask name "Имя профиля для удаления"
  [[ "$name" == "default" ]] && {
    TWPR_err "default лучше rotate, а не remove"
    return 1
  }
  [[ -f "$TWPR_PROFILES_FILE" ]] || { TWPR_err "нет profiles.json"; return 1; }
  TWPR_ask_yn choice "Удалить профиль ${name}" "n"
  [[ "$choice" == "yes" ]] || return 0
  local tmp
  tmp="$(mktemp)"
  jq --arg n "$name" '.profiles |= map(select(.name != $n))' "$TWPR_PROFILES_FILE" >"$tmp"
  install -m 0400 "$tmp" "$TWPR_PROFILES_FILE"
  rm -f "$tmp"
  systemctl restart tproxy-server
  TWPR_ok "Удалён: ${name}"
}
