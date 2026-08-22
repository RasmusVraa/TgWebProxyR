#!/usr/bin/env bash
# TgWebProxyR — entrypoint (ProxyL-style CLI)
set -uo pipefail

TWPR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -d /opt/tgwebproxyr/lib ]] && TWPR_ROOT="/opt/tgwebproxyr"
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
# shellcheck disable=SC1091
source "${TWPR_ROOT}/lib/bot.sh"
# shellcheck disable=SC1091
source "${TWPR_ROOT}/lib/backup.sh"
# shellcheck disable=SC1091
source "${TWPR_ROOT}/lib/docker.sh"
# shellcheck disable=SC1091
source "${TWPR_ROOT}/lib/service.sh"
# shellcheck disable=SC1091
source "${TWPR_ROOT}/lib/menu.sh"

TWPR_usage() {
  cat <<EOF
${C_BOLD}TgWebProxyR${C_RESET} v${TWPR_VERSION}

  ${C_BOLD}Меню${C_RESET}
  tgwebproxyr                 интерактивное меню
  tgwebproxyr menu

  ${C_BOLD}Установка${C_RESET}
  tgwebproxyr setup           мастер (Docker / Native)
  tgwebproxyr setup --docker --quick
  tgwebproxyr setup --native --advanced
  tgwebproxyr install …       то же, что setup

  ${C_BOLD}Прокси${C_RESET}
  tgwebproxyr start|stop|restart
  tgwebproxyr status
  tgwebproxyr health              проверка healthz/readyz/HTTPS
  tgwebproxyr link
  tgwebproxyr logs [unit|svc] [lines]
  tgwebproxyr doctor

  ${C_BOLD}Secrets${C_RESET}
  tgwebproxyr secret list|show|link [name]
  tgwebproxyr secret rotate [name]
  tgwebproxyr secret add [name]
  tgwebproxyr secret remove <name>

  ${C_BOLD}Прочее${C_RESET}
  tgwebproxyr bot …           setup|update|menu|…
  tgwebproxyr backup …        create|list|restore
  tgwebproxyr docker …        setup|up|down|logs|pull
  tgwebproxyr update
  tgwebproxyr uninstall
  tgwebproxyr version | help

Wiki: https://github.com/RasmusVraa/TgWebProxyR/wiki
EOF
}

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    help|-h|--help) TWPR_usage ;;
    version|-V|--version) echo "TgWebProxyR ${TWPR_VERSION}" ;;
    setup|install) TWPR_cmd_setup "$@" ;;
    start) TWPR_cmd_start ;;
    stop) TWPR_cmd_stop "$@" ;;
    restart) TWPR_cmd_restart "$@" ;;
    status) TWPR_cmd_status "$@" ;;
    health|check|probe) TWPR_cmd_health "$@" ;;
    link|links) TWPR_cmd_link "$@" ;;
    logs) TWPR_load_state; TWPR_cmd_logs "$@" ;;
    update) TWPR_cmd_update ;;
    doctor|fix|repair) TWPR_cmd_doctor ;;
    secret)
      case "${1:-}" in
        show) TWPR_cmd_secret_show ;;
        list|ls) TWPR_cmd_secret_list ;;
        link) shift || true; TWPR_cmd_secret_link "${1:-}" ;;
        rotate) shift || true; TWPR_cmd_secret_rotate "${1:-}" ;;
        add) shift || true; TWPR_cmd_secret_add "${1:-}" ;;
        remove|rm|del) shift || true; TWPR_cmd_secret_remove "${1:-}" ;;
        ""|menu) TWPR_menu_secrets ;;
        *) TWPR_err "secret: list|show|link|rotate|add|remove"; exit 2 ;;
      esac
      ;;
    bot) TWPR_cmd_bot "$@" ;;
    backup|backups) TWPR_cmd_backup "$@" ;;
    docker) TWPR_cmd_docker "$@" ;;
    uninstall|remove) TWPR_cmd_uninstall "$@" ;;
    reinstall) TWPR_cmd_reinstall "$@" ;;
    ""|menu|dashboard)
      TWPR_load_state
      if ! TWPR_is_configured; then
        TWPR_cmd_setup
        TWPR_ask_yn _go "Открыть меню" "Y"
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
