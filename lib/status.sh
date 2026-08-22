#!/usr/bin/env bash
# TgWebProxyR — status, health, links

TWPR_cmd_status() {
  TWPR_load_state
  local admin="${TWPR_PORT_ADMIN:-8081}"
  echo ""
  echo -e "  ${C_BOLD}Статус сервисов${C_RESET}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"

  local units=(caddy tproxy-firewall mtproxy tproxy-server)
  local u st
  for u in "${units[@]}"; do
    st="$(TWPR_service_state "$u")"
    case "$st" in
      active)   TWPR_ok "$u — active" ;;
      inactive) TWPR_warn "$u — inactive" ;;
      *)        TWPR_err "$u — не найден" ;;
    esac
  done

  echo ""
  TWPR_info "Порты: HTTP ${TWPR_PORT_HTTP:-80} · HTTPS ${TWPR_PORT_HTTPS:-443} · relay ${TWPR_PORT_RELAY:-8080} · admin ${admin} · mtproxy ${TWPR_PORT_MTPROXY:-2398}"

  echo ""
  if curl -fsS --max-time 3 "http://127.0.0.1:${admin}/healthz" >/dev/null 2>&1; then
    TWPR_ok "relay healthz OK"
  else
    TWPR_warn "relay healthz недоступен"
  fi
  if curl -fsS --max-time 3 "http://127.0.0.1:${admin}/readyz" >/dev/null 2>&1; then
    TWPR_ok "relay readyz OK (backend жив)"
  else
    TWPR_warn "relay readyz = backend не готов"
  fi

  if [[ -n "${TWPR_HOSTNAME:-}" ]]; then
    echo ""
    TWPR_info "Hostname: ${TWPR_HOSTNAME}"
    if [[ "${TWPR_PORT_HTTPS:-443}" == "443" ]]; then
      TWPR_info "Сайт:    https://${TWPR_HOSTNAME}/"
    else
      TWPR_info "Сайт:    https://${TWPR_HOSTNAME}:${TWPR_PORT_HTTPS}/"
      TWPR_warn "Telegram WEB всё равно стучится на :443 — нужен DNAT/фронт"
    fi
  fi
}

TWPR_cmd_link() {
  TWPR_load_state
  if [[ -z "${TWPR_HOSTNAME:-}" || -z "${TWPR_SECRET:-}" ]]; then
    TWPR_err "Прокси ещё не настроен. Запустите: tgwebproxyr setup"
    return 1
  fi
  echo ""
  echo -e "  ${C_BOLD}Ссылки для Telegram Desktop 7.1.1+${C_RESET}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
  echo "  Hostname  ${TWPR_HOSTNAME}"
  echo "  Secret    ${TWPR_SECRET}"
  echo ""
  echo -e "  ${C_BOLD}tg://${C_RESET}"
  echo "  $(TWPR_tg_link)"
  echo ""
  echo -e "  ${C_BOLD}https://t.me${C_RESET}"
  echo "  $(TWPR_web_link)"
  echo ""
  TWPR_info "Settings → Advanced → Connection type → Add proxy → WEB"
  TWPR_info "Hostname без https:// и без порта. Порт всегда 443."
}

TWPR_cmd_metrics() {
  local admin="${TWPR_PORT_ADMIN:-8081}"
  TWPR_load_state
  if ! curl -fsS --max-time 3 "http://127.0.0.1:${admin}/metrics" 2>/dev/null; then
    TWPR_err "Метрики недоступны (нужен работающий tproxy-server)"
    return 1
  fi
}

TWPR_cmd_logs() {
  local unit="${1:-tproxy-server}"
  local lines="${2:-80}"
  journalctl -u "$unit" -u mtproxy -u caddy --no-pager -n "$lines"
}
