#!/usr/bin/env bash
# WebProxyL — secret / profile helpers

WPL_PROFILES_FILE="${WPL_PROFILES_FILE:-/etc/tproxy-server/profiles.json}"

wpl_cmd_secret_show() {
  wpl_load_state
  if [[ -z "${WPL_SECRET:-}" ]]; then
    wpl_err "Secret не сохранён в WebProxyL state"
    return 1
  fi
  echo "$WPL_SECRET"
}

wpl_cmd_secret_rotate() {
  wpl_require_root
  wpl_load_state
  local new_secret
  new_secret="$(wpl_gen_secret)"
  wpl_info "Новый secret: ${C_BOLD}${new_secret}${C_RESET}"
  wpl_confirm "Записать его в profiles.json и перезапустить relay" "Y" || return 0

  if [[ ! -f "$WPL_PROFILES_FILE" ]]; then
    wpl_err "Не найден ${WPL_PROFILES_FILE}"
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
    ' "$WPL_PROFILES_FILE" >"$tmp"
    install -m 0400 "$tmp" "$WPL_PROFILES_FILE"
    rm -f "$tmp"
  else
    wpl_err "Нужен jq для ротации secret"
    return 1
  fi

  # Official MTProxy also needs -S updated
  if [[ -f /etc/mtproxy/mtproxy.env ]]; then
    sed -i "s/^MTPROXY_SECRET=.*/MTPROXY_SECRET=${new_secret}/" /etc/mtproxy/mtproxy.env || true
  fi

  WPL_SECRET="$new_secret"
  wpl_save_state
  systemctl restart mtproxy tproxy-server
  wpl_ok "Secret обновлён"
  wpl_cmd_link
}

wpl_cmd_secret_add() {
  wpl_require_root
  wpl_load_state
  local name secret backend
  name="$(wpl_prompt "Имя профиля" "user$(date +%s | tail -c 5)")"
  secret="$(wpl_gen_secret)"
  backend="$(wpl_prompt "Backend loopback" "127.0.0.1:2398")"
  wpl_info "Secret для ${name}: ${secret}"

  [[ -f "$WPL_PROFILES_FILE" ]] || {
    wpl_err "Сначала выполните setup"
    return 1
  }

  local tmp
  tmp="$(mktemp)"
  jq --arg n "$name" --arg s "$secret" --arg b "$backend" '
    .profiles += [{name:$n, secret:$s, backend:$b, carrier_mode:"https"}]
  ' "$WPL_PROFILES_FILE" >"$tmp"
  install -m 0400 "$tmp" "$WPL_PROFILES_FILE"
  rm -f "$tmp"
  systemctl restart tproxy-server
  wpl_ok "Профиль ${name} добавлен"
  echo "  $(wpl_tg_link "${WPL_HOSTNAME}" "$secret")"
  echo "  $(wpl_web_link "${WPL_HOSTNAME}" "$secret")"
  wpl_warn "Если backend общий — все профили делят один MTProxy. Для квот поднимите отдельный listener."
}
