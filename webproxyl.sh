#!/usr/bin/env bash
# WebProxyL — interactive menu + CLI
set -euo pipefail

WPL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Prefer installed location when invoked via /usr/local/bin
if [[ -d /opt/webproxyl/lib ]]; then
  WPL_ROOT="/opt/webproxyl"
fi
export WPL_ROOT
WPL_VERSION="$(tr -d '[:space:]' <"${WPL_ROOT}/version" 2>/dev/null || echo "dev")"
export WPL_VERSION

# shellcheck disable=SC1091
source "${WPL_ROOT}/lib/colors.sh"
# shellcheck disable=SC1091
source "${WPL_ROOT}/lib/utils.sh"
# shellcheck disable=SC1091
source "${WPL_ROOT}/lib/status.sh"
# shellcheck disable=SC1091
source "${WPL_ROOT}/lib/deploy.sh"
# shellcheck disable=SC1091
source "${WPL_ROOT}/lib/secrets.sh"
# shellcheck disable=SC1091
source "${WPL_ROOT}/lib/uninstall.sh"

wpl_usage() {
  cat <<EOF
${C_BOLD}WebProxyL${C_RESET} v${WPL_VERSION} — менеджер Telegram WEB Proxy

${C_ACCENT}Использование:${C_RESET}
  webproxyl                 интерактивное меню
  webproxyl setup           мастер установки
  webproxyl status          статус сервисов
  webproxyl link            ссылки tg:// и t.me/webproxy
  webproxyl logs [unit]     journalctl (по умолчанию tproxy-server)
  webproxyl metrics         метрики relay
  webproxyl update          обновить relay (tproxy-server)
  webproxyl reinstall       повторный официальный install
  webproxyl secret show     показать secret
  webproxyl secret rotate   сгенерировать новый secret
  webproxyl secret add      добавить профиль (мульти-secret)
  webproxyl uninstall       удалить установку
  webproxyl help            эта справка

${C_DIM}Движок: https://github.com/telegramdesktop/tproxy-server
Клиент: Telegram Desktop 7.1.1+ (тип прокси WEB)${C_RESET}
EOF
}

wpl_menu() {
  while true; do
    clear 2>/dev/null || true
    wpl_banner
    wpl_load_state
    if [[ -n "${WPL_HOSTNAME:-}" ]]; then
      echo -e "  ${C_DIM}host${C_RESET} ${WPL_HOSTNAME}  ${C_DIM}·${C_RESET}  $(wpl_service_state tproxy-server)"
      echo ""
    fi
    echo -e "  ${C_BOLD}1${C_RESET}) Установка / мастер"
    echo -e "  ${C_BOLD}2${C_RESET}) Статус"
    echo -e "  ${C_BOLD}3${C_RESET}) Ссылки для клиентов"
    echo -e "  ${C_BOLD}4${C_RESET}) Логи"
    echo -e "  ${C_BOLD}5${C_RESET}) Обновить relay"
    echo -e "  ${C_BOLD}6${C_RESET}) Ротация secret"
    echo -e "  ${C_BOLD}7${C_RESET}) Добавить профиль"
    echo -e "  ${C_BOLD}8${C_RESET}) Метрики"
    echo -e "  ${C_BOLD}9${C_RESET}) Удалить"
    echo -e "  ${C_BOLD}0${C_RESET}) Выход"
    echo ""
    local choice
    read -r -p "  Выберите пункт: " choice || true
    case "$choice" in
      1) wpl_cmd_setup; wpl_pause ;;
      2) wpl_cmd_status; wpl_pause ;;
      3) wpl_cmd_link; wpl_pause ;;
      4) wpl_cmd_logs; wpl_pause ;;
      5) wpl_cmd_update; wpl_pause ;;
      6) wpl_cmd_secret_rotate; wpl_pause ;;
      7) wpl_cmd_secret_add; wpl_pause ;;
      8) wpl_cmd_metrics; wpl_pause ;;
      9) wpl_cmd_uninstall; wpl_pause ;;
      0|q|Q) exit 0 ;;
      *) wpl_warn "Неизвестный пункт"; sleep 1 ;;
    esac
  done
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    ""|menu) wpl_menu ;;
    setup|install) wpl_cmd_setup "$@" ;;
    status) wpl_cmd_status "$@" ;;
    link|links) wpl_cmd_link "$@" ;;
    logs) wpl_cmd_logs "$@" ;;
    metrics) wpl_cmd_metrics "$@" ;;
    update) wpl_cmd_update "$@" ;;
    reinstall) wpl_cmd_reinstall "$@" ;;
    secret)
      case "${1:-}" in
        show) wpl_cmd_secret_show ;;
        rotate) wpl_cmd_secret_rotate ;;
        add) wpl_cmd_secret_add ;;
        *) wpl_err "secret: show|rotate|add"; exit 2 ;;
      esac
      ;;
    uninstall|remove) wpl_cmd_uninstall "$@" ;;
    help|-h|--help) wpl_usage ;;
    version|-V|--version) echo "WebProxyL ${WPL_VERSION}" ;;
    *)
      wpl_err "Неизвестная команда: $cmd"
      wpl_usage
      exit 2
      ;;
  esac
}

main "$@"
