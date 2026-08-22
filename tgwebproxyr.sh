#!/usr/bin/env bash
# TgWebProxyR — interactive menu + CLI
set -euo pipefail

TWPR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Prefer installed location when invoked via /usr/local/bin
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
source "${TWPR_ROOT}/lib/status.sh"
# shellcheck disable=SC1091
source "${TWPR_ROOT}/lib/deploy.sh"
# shellcheck disable=SC1091
source "${TWPR_ROOT}/lib/secrets.sh"
# shellcheck disable=SC1091
source "${TWPR_ROOT}/lib/uninstall.sh"

TWPR_usage() {
  cat <<EOF
${C_BOLD}TgWebProxyR${C_RESET} v${TWPR_VERSION} — менеджер Telegram WEB Proxy

${C_ACCENT}Использование:${C_RESET}
  tgwebproxyr                 интерактивное меню
  tgwebproxyr setup           мастер установки
  tgwebproxyr status          статус сервисов
  tgwebproxyr link            ссылки tg:// и t.me/webproxy
  tgwebproxyr logs [unit]     journalctl (по умолчанию tproxy-server)
  tgwebproxyr metrics         метрики relay
  tgwebproxyr update          обновить relay (tproxy-server)
  tgwebproxyr reinstall       повторный официальный install
  tgwebproxyr secret show     показать secret
  tgwebproxyr secret rotate   сгенерировать новый secret
  tgwebproxyr secret add      добавить профиль (мульти-secret)
  tgwebproxyr uninstall       удалить установку
  tgwebproxyr help            эта справка

${C_DIM}Движок: https://github.com/telegramdesktop/tproxy-server
Клиент: Telegram Desktop 7.1.1+ (тип прокси WEB)${C_RESET}
EOF
}

TWPR_menu() {
  while true; do
    clear 2>/dev/null || true
    TWPR_banner
    TWPR_load_state
    if [[ -n "${TWPR_HOSTNAME:-}" ]]; then
      echo -e "  ${C_DIM}host${C_RESET} ${TWPR_HOSTNAME}  ${C_DIM}·${C_RESET}  $(TWPR_service_state tproxy-server)"
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
      1) TWPR_cmd_setup; TWPR_pause ;;
      2) TWPR_cmd_status; TWPR_pause ;;
      3) TWPR_cmd_link; TWPR_pause ;;
      4) TWPR_cmd_logs; TWPR_pause ;;
      5) TWPR_cmd_update; TWPR_pause ;;
      6) TWPR_cmd_secret_rotate; TWPR_pause ;;
      7) TWPR_cmd_secret_add; TWPR_pause ;;
      8) TWPR_cmd_metrics; TWPR_pause ;;
      9) TWPR_cmd_uninstall; TWPR_pause ;;
      0|q|Q) exit 0 ;;
      *) TWPR_warn "Неизвестный пункт"; sleep 1 ;;
    esac
  done
}

main() {
  local cmd="${1:-}"
  shift || true
  case "$cmd" in
    ""|menu) TWPR_menu ;;
    setup|install) TWPR_cmd_setup "$@" ;;
    status) TWPR_cmd_status "$@" ;;
    link|links) TWPR_cmd_link "$@" ;;
    logs) TWPR_cmd_logs "$@" ;;
    metrics) TWPR_cmd_metrics "$@" ;;
    update) TWPR_cmd_update "$@" ;;
    reinstall) TWPR_cmd_reinstall "$@" ;;
    secret)
      case "${1:-}" in
        show) TWPR_cmd_secret_show ;;
        rotate) TWPR_cmd_secret_rotate ;;
        add) TWPR_cmd_secret_add ;;
        *) TWPR_err "secret: show|rotate|add"; exit 2 ;;
      esac
      ;;
    uninstall|remove) TWPR_cmd_uninstall "$@" ;;
    help|-h|--help) TWPR_usage ;;
    version|-V|--version) echo "TgWebProxyR ${TWPR_VERSION}" ;;
    *)
      TWPR_err "Неизвестная команда: $cmd"
      TWPR_usage
      exit 2
      ;;
  esac
}

main "$@"
