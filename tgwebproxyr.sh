#!/usr/bin/env bash
# TgWebProxyR — entrypoint (Docker-first CLI)
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

TWPR_usage() {
  cat <<EOF
${C_BOLD}TgWebProxyR${C_RESET} v${TWPR_VERSION} · Docker

  tgwebproxyr              меню
  tgwebproxyr setup        установка / переустановка (Docker)
  tgwebproxyr status       статус
  tgwebproxyr link         ссылки
  tgwebproxyr logs         логи compose
  tgwebproxyr docker …     up|down|logs|pull
  tgwebproxyr bot …        setup|update|menu
  tgwebproxyr backup …
  tgwebproxyr uninstall
EOF
}

TWPR_dashboard() {
  while true; do
    clear 2>/dev/null || true
    TWPR_banner
    TWPR_load_state

    local st_relay st_mp st_caddy health hz
    if TWPR_is_docker || [[ -f "${TWPR_ROOT}/docker/.env" ]]; then
      TWPR_DEPLOY_MODE=docker
      st_mp="$(TWPR_docker_container_state mtproxy 2>/dev/null || echo missing)"
      st_relay="$(TWPR_docker_container_state relay 2>/dev/null || echo missing)"
      st_caddy="$(TWPR_docker_container_state caddy 2>/dev/null || echo missing)"
    else
      st_relay=missing; st_mp=missing; st_caddy=missing
    fi
    hz="$(TWPR_health_probe 2>/dev/null || echo down)"
    case "$hz" in
      ready) health="${C_GREEN}ready${C_RESET}" ;;
      alive) health="${C_YELLOW}alive${C_RESET}" ;;
      *)     health="${C_RED}down${C_RESET}" ;;
    esac

    if [[ -n "${TWPR_HOSTNAME:-}" ]]; then
      echo -e "  ${C_BOLD}${TWPR_HOSTNAME}${C_RESET}"
      echo -e "  $(TWPR_fmt_svc relay "$st_relay")  $(TWPR_fmt_svc mtproxy "$st_mp")  $(TWPR_fmt_svc caddy "$st_caddy")  · ${health}"
    else
      echo -e "  ${C_YELLOW}ещё не установлено${C_RESET}"
    fi
    echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
    echo ""
    echo -e "  ${C_BOLD}1${C_RESET})  Ссылка"
    echo -e "  ${C_BOLD}2${C_RESET})  Статус"
    echo -e "  ${C_BOLD}3${C_RESET})  Логи"
    echo -e "  ${C_BOLD}4${C_RESET})  Обновить образы / стек"
    echo -e "  ${C_BOLD}5${C_RESET})  Установка заново"
    echo -e "  ${C_BOLD}6${C_RESET})  Telegram-бот"
    echo -e "  ${C_BOLD}7${C_RESET})  Бэкапы"
    echo -e "  ${C_BOLD}8${C_RESET})  Удалить"
    echo -e "  ${C_BOLD}0${C_RESET})  Выход"
    echo ""

    local choice=""
    read -r -p "  › " choice || true
    case "$choice" in
      1) TWPR_cmd_link; TWPR_pause ;;
      2) TWPR_cmd_status; TWPR_pause ;;
      3) TWPR_cmd_logs; TWPR_pause ;;
      4)
        TWPR_docker_ensure_env 2>/dev/null || true
        TWPR_IMAGE_TAG="$(tr -d '[:space:]' <"${TWPR_ROOT}/version" 2>/dev/null || echo latest)"
        TWPR_docker_write_env 2>/dev/null || true
        TWPR_docker_up
        TWPR_pause
        ;;
      5) export TWPR_SETUP_MODE=docker; TWPR_cmd_setup; TWPR_pause ;;
      6) TWPR_bot_menu; TWPR_pause ;;
      7)
        TWPR_backup_list
        TWPR_ask_yn bchoice "Новый бэкап" "Y"
        [[ "${bchoice:-}" == "yes" ]] && TWPR_backup_create
        TWPR_pause
        ;;
      8) TWPR_cmd_uninstall; TWPR_pause ;;
      0|q|Q) exit 0 ;;
      *) ;;
    esac
  done
}

main() {
  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    help|-h|--help) TWPR_usage ;;
    version|-V|--version) echo "TgWebProxyR ${TWPR_VERSION}" ;;
    setup|install)
      export TWPR_SETUP_MODE=docker
      TWPR_cmd_setup
      ;;
    status) TWPR_cmd_status "$@" ;;
    link|links) TWPR_cmd_link "$@" ;;
    logs) TWPR_load_state; TWPR_cmd_logs "$@" ;;
    update)
      TWPR_load_state
      TWPR_IMAGE_TAG="$(tr -d '[:space:]' <"${TWPR_ROOT}/version")"
      TWPR_docker_up
      ;;
    doctor|fix|repair)
      TWPR_require_root
      TWPR_load_state
      TWPR_cmd_docker restart
      TWPR_cmd_status
      ;;
    secret)
      case "${1:-}" in
        show) TWPR_cmd_secret_show ;;
        rotate) TWPR_cmd_secret_rotate ;;
        add) TWPR_cmd_secret_add ;;
        *) TWPR_err "secret: show|rotate|add"; exit 2 ;;
      esac
      ;;
    bot) TWPR_cmd_bot "$@" ;;
    backup|backups) TWPR_cmd_backup "$@" ;;
    docker) TWPR_cmd_docker "$@" ;;
    uninstall|remove) TWPR_cmd_uninstall "$@" ;;
    ""|menu|dashboard)
      TWPR_load_state
      if ! TWPR_is_configured; then
        export TWPR_SETUP_MODE=docker
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
