#!/usr/bin/env bash
# TgWebProxyR — Shop API (для внешних магазинов)

TWPR_API_ENV="${TWPR_STATE_DIR}/api.env"
TWPR_API_UNIT="/etc/systemd/system/tgwebproxyr-api.service"
TWPR_API_PORT="${TWPR_API_PORT:-8787}"

TWPR_cmd_api() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    setup|install) TWPR_api_setup ;;
    status) TWPR_api_status ;;
    token) TWPR_api_show_token ;;
    rotate) TWPR_api_rotate_token ;;
    start) systemctl enable --now tgwebproxyr-api.service; TWPR_api_status ;;
    stop) systemctl stop tgwebproxyr-api.service; TWPR_ok "api stopped" ;;
    restart) systemctl restart tgwebproxyr-api.service; TWPR_api_status ;;
    logs) journalctl -u tgwebproxyr-api -n "${1:-60}" --no-pager ;;
    *)
      cat <<EOF
  tgwebproxyr api setup     создать token + systemd (127.0.0.1:${TWPR_API_PORT})
  tgwebproxyr api status
  tgwebproxyr api token
  tgwebproxyr api rotate
  tgwebproxyr api start|stop|restart|logs

Пример:
  curl -s -H "Authorization: Bearer \$TOKEN" http://127.0.0.1:${TWPR_API_PORT}/v1/users
  curl -s -H "Authorization: Bearer \$TOKEN" -H "Content-Type: application/json" \\
    -d '{"name":"shop_user1"}' http://127.0.0.1:${TWPR_API_PORT}/v1/users
EOF
      ;;
  esac
}

TWPR_api_write_unit() {
  cat >"$TWPR_API_UNIT" <<EOF
[Unit]
Description=TgWebProxyR Shop API
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/tgwebproxyr/bot
Environment=TWPR_STATE_DIR=/etc/tgwebproxyr
Environment=TWPR_API_HOST=127.0.0.1
Environment=TWPR_API_PORT=${TWPR_API_PORT}
EnvironmentFile=-/etc/tgwebproxyr/api.env
ExecStart=/usr/bin/python3 /opt/tgwebproxyr/bot/twpr_api.py
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF
  chmod 0644 "$TWPR_API_UNIT"
  systemctl daemon-reload
}

TWPR_api_setup() {
  TWPR_require_root
  mkdir -p "$TWPR_STATE_DIR" /opt/tgwebproxyr/bot
  if [[ -f "${TWPR_ROOT}/bot/twpr_api.py" ]]; then
    cp -a "${TWPR_ROOT}/bot/twpr_api.py" /opt/tgwebproxyr/bot/twpr_api.py
  fi
  local token=""
  if [[ -f "$TWPR_API_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$TWPR_API_ENV" 2>/dev/null || true
    token="${TWPR_API_TOKEN:-}"
  fi
  if [[ -z "$token" ]]; then
    token="$(TWPR_gen_secret)$(TWPR_gen_secret)"
    token="${token:0:48}"
  fi
  umask 077
  cat >"$TWPR_API_ENV" <<EOF
TWPR_API_TOKEN=${token}
TWPR_API_HOST=127.0.0.1
TWPR_API_PORT=${TWPR_API_PORT}
EOF
  chmod 600 "$TWPR_API_ENV"
  TWPR_api_write_unit
  systemctl enable --now tgwebproxyr-api.service
  echo ""
  TWPR_ok "API слушает 127.0.0.1:${TWPR_API_PORT}"
  TWPR_info "Token (сохраните):"
  echo "  ${token}"
  echo ""
  TWPR_info "Документация: tgwebproxyr api"
  TWPR_api_status
}

TWPR_api_status() {
  echo ""
  echo -e "  ${C_BOLD}Shop API${C_RESET}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
  local st
  st="$(TWPR_service_state tgwebproxyr-api.service)"
  case "$st" in
    active) TWPR_ok "service active · http://127.0.0.1:${TWPR_API_PORT}" ;;
    *) TWPR_warn "service ${st} — tgwebproxyr api setup" ;;
  esac
  if [[ -f "$TWPR_API_ENV" ]]; then
    TWPR_ok "token configured"
  else
    TWPR_warn "нет ${TWPR_API_ENV}"
  fi
}

TWPR_api_show_token() {
  TWPR_require_root
  [[ -f "$TWPR_API_ENV" ]] || { TWPR_err "сначала api setup"; return 1; }
  # shellcheck disable=SC1090
  source "$TWPR_API_ENV"
  echo "${TWPR_API_TOKEN}"
}

TWPR_api_rotate_token() {
  TWPR_require_root
  local token
  token="$(TWPR_gen_secret)$(TWPR_gen_secret)"
  token="${token:0:48}"
  umask 077
  cat >"$TWPR_API_ENV" <<EOF
TWPR_API_TOKEN=${token}
TWPR_API_HOST=127.0.0.1
TWPR_API_PORT=${TWPR_API_PORT}
EOF
  chmod 600 "$TWPR_API_ENV"
  systemctl restart tgwebproxyr-api.service 2>/dev/null || true
  TWPR_ok "новый token:"
  echo "  ${token}"
}
