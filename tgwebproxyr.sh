#!/usr/bin/env bash
# TgWebProxyR — entrypoint: wizard + dashboard
set -uo pipefail

TWPR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d /opt/tgwebproxyr/lib ]]; then
  TWPR_ROOT="/opt/tgwebproxyr"
fi
export TWPR_ROOT
TWPR_VERSION="$(tr -d '[:space:]' <"${TWPR_ROOT}/version" 2>/dev/null || echo "dev")"
export TWPR_VERSION

# shellcheck disable=SC1091
source "${TWPR_ROOT}/lib/colors.sh"
# shellcheck disable=SC1091
source "${TWPR_ROOT}/lib/utils.sh"
# shellcheck disable=SC1091
source "${TWPR_ROOT}/lib/ports.sh"
# shellcheck disable=SC1091
source "${TWPR_ROOT}/lib/status.sh"
# shellcheck disable=SC1091
source "${TWPR_ROOT}/lib/deploy.sh"
# shellcheck disable=SC1091
source "${TWPR_ROOT}/lib/secrets.sh"
# shellcheck disable=SC1091
source "${TWPR_ROOT}/lib/uninstall.sh"

TWPR_usage() {
  cat <<EOF
${C_BOLD}TgWebProxyR${C_RESET} v${TWPR_VERSION}

  tgwebproxyr              дашборд (или мастер, если ещё не установлено)
  tgwebproxyr setup        полный пошаговый мастер установки
  tgwebproxyr status       статус сервисов
  tgwebproxyr link         ссылки для Telegram
  tgwebproxyr logs         journalctl
  tgwebproxyr update       обновить relay
  tgwebproxyr doctor       починить / дождаться ready
  tgwebproxyr reinstall    переустановка
  tgwebproxyr secret ...   show | rotate | add
  tgwebproxyr uninstall    удалить
  tgwebproxyr help

Клиент: Telegram Desktop 7.1.1+ → Add proxy → WEB
EOF
}

TWPR_dashboard() {
  while true; do
    clear 2>/dev/null || true
    TWPR_banner
    TWPR_load_state

    local st_relay st_mp st_caddy health="—"
    st_relay="$(TWPR_service_state tproxy-server)"
    st_mp="$(TWPR_service_state mtproxy)"
    st_caddy="$(TWPR_service_state caddy)"
    if curl -fsS --max-time 2 "http://127.0.0.1:${TWPR_PORT_ADMIN:-8081}/readyz" >/dev/null 2>&1; then
      health="${C_GREEN}ready${C_RESET}"
    elif curl -fsS --max-time 2 "http://127.0.0.1:${TWPR_PORT_ADMIN:-8081}/healthz" >/dev/null 2>&1; then
      health="${C_YELLOW}alive / backend down${C_RESET}"
    else
      health="${C_RED}down${C_RESET}"
    fi

    if [[ -n "${TWPR_HOSTNAME:-}" ]]; then
      echo -e "  host    ${C_BOLD}${TWPR_HOSTNAME}${C_RESET}"
      echo -e "  ports   HTTP ${TWPR_PORT_HTTP:-80} · HTTPS ${TWPR_PORT_HTTPS:-443} · relay ${TWPR_PORT_RELAY:-8080}"
      echo -e "  relay   ${st_relay}   mtproxy ${st_mp}   caddy ${st_caddy}"
      echo -e "  health  ${health}"
    else
      echo -e "  ${C_YELLOW}Прокси ещё не настроен${C_RESET}"
    fi
    echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
    echo ""
    echo -e "  ${C_BOLD}1${C_RESET})  Ссылка для Telegram"
    echo -e "  ${C_BOLD}2${C_RESET})  Статус сервисов"
    echo -e "  ${C_BOLD}3${C_RESET})  Логи"
    echo -e "  ${C_BOLD}4${C_RESET})  Обновить relay"
    echo -e "  ${C_BOLD}5${C_RESET})  Сменить / заново установить"
    echo -e "  ${C_BOLD}6${C_RESET})  Ротация secret"
    echo -e "  ${C_BOLD}7${C_RESET})  Добавить ещё один secret"
    echo -e "  ${C_BOLD}8${C_RESET})  Удалить всё"
    echo -e "  ${C_BOLD}0${C_RESET})  Выход"
    echo ""

    local choice=""
    read -r -p "  Выберите: " choice || true
    case "$choice" in
      1) TWPR_cmd_link; TWPR_pause ;;
      2) TWPR_cmd_status; TWPR_pause ;;
      3) TWPR_cmd_logs; TWPR_pause ;;
      4) TWPR_cmd_update; TWPR_pause ;;
      5) TWPR_cmd_setup; TWPR_pause ;;
      6) TWPR_cmd_secret_rotate; TWPR_pause ;;
      7) TWPR_cmd_secret_add; TWPR_pause ;;
      8) TWPR_cmd_uninstall; TWPR_pause ;;
      0|q|Q) exit 0 ;;
      *) TWPR_warn "Неизвестный пункт"; sleep 1 ;;
    esac
  done
}

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    help|-h|--help)
      TWPR_usage
      ;;
    version|-V|--version)
      echo "TgWebProxyR ${TWPR_VERSION}"
      ;;
    setup|install)
      TWPR_cmd_setup "$@"
      ;;
    status)
      TWPR_cmd_status "$@"
      ;;
    link|links)
      TWPR_cmd_link "$@"
      ;;
    logs)
      TWPR_cmd_logs "$@"
      ;;
    metrics)
      TWPR_cmd_metrics "$@"
      ;;
    update)
      TWPR_cmd_update "$@"
      ;;
    doctor|fix|repair)
      TWPR_require_root
      TWPR_load_state
      TWPR_ensure_relay_ready
      ;;
    reinstall)
      TWPR_cmd_reinstall "$@"
      ;;
    secret)
      case "${1:-}" in
        show) TWPR_cmd_secret_show ;;
        rotate) TWPR_cmd_secret_rotate ;;
        add) TWPR_cmd_secret_add ;;
        *) TWPR_err "secret: show|rotate|add"; exit 2 ;;
      esac
      ;;
    uninstall|remove)
      TWPR_cmd_uninstall "$@"
      ;;
    ""|menu|dashboard)
      TWPR_load_state
      if ! TWPR_is_configured; then
        TWPR_info "Первый запуск — открываю мастер установки"
        sleep 1
        TWPR_cmd_setup
        echo ""
        TWPR_ask_yn _go "Открыть меню управления" "Y"
        [[ "${_go:-}" == "yes" ]] && TWPR_dashboard
      else
        TWPR_dashboard
      fi
      ;;
    *)
      TWPR_err "Неизвестная команда: $cmd"
      TWPR_usage
      exit 2
      ;;
  esac
}

main "$@"
