#!/usr/bin/env bash
# TgWebProxyR — secret / profile helpers

TWPR_PROFILES_FILE="${TWPR_PROFILES_FILE:-/etc/tproxy-server/profiles.json}"

TWPR_cmd_secret_show() {
  TWPR_load_state
  if [[ -z "${TWPR_SECRET:-}" ]]; then
    TWPR_err "Secret не сохранён в TgWebProxyR state"
    return 1
  fi
  echo "$TWPR_SECRET"
}

TWPR_cmd_secret_rotate() {
  TWPR_require_root
  TWPR_load_state
  local new_secret
  new_secret="$(TWPR_gen_secret)"
  TWPR_info "Новый secret: ${C_BOLD}${new_secret}${C_RESET}"
  TWPR_confirm "Записать его в profiles.json и перезапустить relay" "Y" || return 0

  if [[ ! -f "$TWPR_PROFILES_FILE" ]]; then
    TWPR_err "Не найден ${TWPR_PROFILES_FILE}"
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    local tmp
    tmp="$(mktemp)"
    jq --arg s "$new_secret" '
      .profiles |= map(if .name == "default" or length == 1 then .secret = $s else . end)
      | if (.profiles | length) == 0 then
          {profiles:[{name:"default",secret:$s,backend:"127.0.0.1:2398",carrier_mode:"https"}]}
        else . end
    ' "$TWPR_PROFILES_FILE" >"$tmp"
    install -m 0400 "$tmp" "$TWPR_PROFILES_FILE"
    rm -f "$tmp"
  else
    TWPR_err "Нужен jq для ротации secret"
    return 1
  fi

  # Official MTProxy also needs -S updated
  if [[ -f /etc/mtproxy/mtproxy.env ]]; then
    sed -i "s/^MTPROXY_SECRET=.*/MTPROXY_SECRET=${new_secret}/" /etc/mtproxy/mtproxy.env || true
  fi

  TWPR_SECRET="$new_secret"
  TWPR_save_state
  systemctl restart mtproxy tproxy-server
  TWPR_ok "Secret обновлён"
  TWPR_cmd_link
}

TWPR_cmd_secret_add() {
  TWPR_require_root
  TWPR_load_state
  local name secret backend
  name="$(TWPR_prompt "Имя профиля" "user$(date +%s | tail -c 5)")"
  secret="$(TWPR_gen_secret)"
  backend="$(TWPR_prompt "Backend loopback" "127.0.0.1:2398")"
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
  TWPR_warn "Если backend общий — все профили делят один MTProxy. Для квот поднимите отдельный listener."
}
