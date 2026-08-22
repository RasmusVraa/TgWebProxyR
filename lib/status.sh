#!/usr/bin/env bash
# WebProxyL — status, health, links

wpl_cmd_status() {
  wpl_load_state
  wpl_sec "Статус сервисов"

  local units=(caddy tproxy-firewall mtproxy tproxy-server)
  local u st
  for u in "${units[@]}"; do
    st="$(wpl_service_state "$u")"
    case "$st" in
      active)   wpl_ok "$u — ${C_GREEN}active${C_RESET}" ;;
      inactive) wpl_warn "$u — inactive" ;;
      *)        wpl_err "$u — не найден" ;;
    esac
  done

  echo ""
  if curl -fsS --max-time 3 http://127.0.0.1:8081/healthz >/dev/null 2>&1; then
    wpl_ok "relay healthz OK"
  else
    wpl_warn "relay healthz недоступен"
  fi
  if curl -fsS --max-time 3 http://127.0.0.1:8081/readyz >/dev/null 2>&1; then
    wpl_ok "relay readyz OK (backend жив)"
  else
    wpl_warn "relay readyz = backend не готов"
  fi

  if [[ -n "${WPL_HOSTNAME:-}" ]]; then
    echo ""
    wpl_info "Hostname: ${C_BOLD}${WPL_HOSTNAME}${C_RESET}"
    wpl_info "Сайт:    https://${WPL_HOSTNAME}/"
  fi
}

wpl_cmd_link() {
  wpl_load_state
  if [[ -z "${WPL_HOSTNAME:-}" || -z "${WPL_SECRET:-}" ]]; then
    wpl_err "Прокси ещё не настроен. Запустите: webproxyl setup"
    return 1
  fi
  wpl_sec "Ссылки для клиентов (Telegram ≥ 7.1.1 Desktop)"
  echo -e "  ${C_DIM}Hostname${C_RESET}  ${WPL_HOSTNAME}"
  echo -e "  ${C_DIM}Secret${C_RESET}    ${WPL_SECRET}"
  echo ""
  echo -e "  ${C_BOLD}tg://${C_RESET}"
  echo "  $(wpl_tg_link)"
  echo ""
  echo -e "  ${C_BOLD}https://t.me${C_RESET}"
  echo "  $(wpl_web_link)"
  echo ""
  wpl_info "В клиенте: Settings → Advanced → Connection type → Add proxy → WEB"
  wpl_info "Hostname без https:// и без порта. Порт всегда 443."
}

wpl_cmd_metrics() {
  if ! curl -fsS --max-time 3 http://127.0.0.1:8081/metrics 2>/dev/null; then
    wpl_err "Метрики недоступны (нужен работающий tproxy-server)"
    return 1
  fi
}

wpl_cmd_logs() {
  local unit="${1:-tproxy-server}"
  local lines="${2:-80}"
  journalctl -u "$unit" -u mtproxy -u caddy --no-pager -n "$lines"
}
