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
# shellcheck disable=SC1091
source "${TWPR_ROOT}/lib/bot.sh"
# shellcheck disable=SC1091
source "${TWPR_ROOT}/lib/backup.sh"
# shellcheck disable=SC1091
source "${TWPR_ROOT}/lib/docker.sh"

TWPR_usage() {
  cat <<EOF
${C_BOLD}TgWebProxyR${C_RESET} v${TWPR_VERSION}

  tgwebproxyr              дашборд (или мастер, если ещё не установлено)
  tgwebproxyr setup        мастер: быстро / Docker / расширенно
  tgwebproxyr setup --quick
  tgwebproxyr setup --docker
  tgwebproxyr docker …     up|down|status|logs|link|setup
  tgwebproxyr status       статус сервисов
  tgwebproxyr link         ссылки для Telegram
  tgwebproxyr logs         journalctl / docker logs
  tgwebproxyr update       обновить relay
  tgwebproxyr doctor       починить / дождаться ready
  tgwebproxyr reinstall    переустановка
  tgwebproxyr secret ...   show | rotate | add
  tgwebproxyr bot ...      setup|status|start|stop|restart|logs
  tgwebproxyr backup ...   create|list|restore <name>
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

    local st_relay st_mp st_caddy health mode_label
    local hz

    if TWPR_is_docker; then
      mode_label="docker"
      st_mp="$(TWPR_docker_container_state mtproxy)"
      st_relay="$(TWPR_docker_container_state relay)"
      st_caddy="$(TWPR_docker_container_state caddy)"
    else
      mode_label="native"
      st_relay="$(TWPR_service_state tproxy-server)"
      st_mp="$(TWPR_service_state mtproxy)"
      st_caddy="$(TWPR_service_state caddy)"
    fi

    hz="$(TWPR_health_probe)"
    case "$hz" in
      ready) health="${C_GREEN}ready${C_RESET}" ;;
      alive) health="${C_YELLOW}alive / backend down${C_RESET}" ;;
      *)     health="${C_RED}down${C_RESET}" ;;
    esac

    if [[ -n "${TWPR_HOSTNAME:-}" ]]; then
      echo -e "  host    ${C_BOLD}${TWPR_HOSTNAME}${C_RESET}  ${C_DIM}(${mode_label})${C_RESET}"
      echo -e "  ports   HTTP ${TWPR_PORT_HTTP:-80} · HTTPS ${TWPR_PORT_HTTPS:-443}"
      echo -e "  stack   $(TWPR_fmt_svc relay "$st_relay")  $(TWPR_fmt_svc mtproxy "$st_mp")  $(TWPR_fmt_svc caddy "$st_caddy")"
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
    echo -e "  ${C_BOLD}8${C_RESET})  Telegram-бот"
    echo -e "  ${C_BOLD}9${C_RESET})  Бэкапы"
    echo -e "  ${C_BOLD}10${C_RESET}) Docker Compose"
    echo -e "  ${C_BOLD}11${C_RESET}) Удалить всё"
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
      8) TWPR_bot_setup; TWPR_pause ;;
      9)
        TWPR_backup_list
        echo ""
        local bchoice=""
        TWPR_ask_yn bchoice "Создать новый бэкап" "Y"
        [[ "$bchoice" == "yes" ]] && TWPR_backup_create
        TWPR_pause
        ;;
      10) TWPR_cmd_docker; TWPR_pause ;;
      11) TWPR_cmd_uninstall; TWPR_pause ;;
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
      # flags: --quick --docker --advanced --yes
      for a in "$@"; do
        case "$a" in
          --quick|-q) export TWPR_SETUP_MODE="quick" ;;
          --docker|-d) export TWPR_SETUP_MODE="docker" ;;
          --advanced|-a) export TWPR_SETUP_MODE="advanced" ;;
          --yes|-y) export TWPR_YES=1 ;;
        esac
      done
      TWPR_cmd_setup
      ;;
    status)
      TWPR_cmd_status "$@"
      ;;
    link|links)
      TWPR_cmd_link "$@"
      ;;
    logs)
      TWPR_load_state
      if [[ "${TWPR_DEPLOY_MODE:-}" == "docker" ]]; then
        TWPR_cmd_docker logs "$@"
      else
        TWPR_cmd_logs "$@"
      fi
      ;;
    metrics)
      TWPR_cmd_metrics "$@"
      ;;
    update)
      TWPR_load_state
      if [[ "${TWPR_DEPLOY_MODE:-}" == "docker" ]]; then
        TWPR_cmd_docker build
        TWPR_cmd_docker up
      else
        TWPR_cmd_update "$@"
      fi
      ;;
    doctor|fix|repair)
      TWPR_require_root
      TWPR_load_state
      if [[ "${TWPR_DEPLOY_MODE:-}" == "docker" ]]; then
        TWPR_cmd_docker restart
        TWPR_cmd_docker status
      else
        TWPR_ensure_relay_ready
      fi
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
    bot)
      TWPR_cmd_bot "$@"
      ;;
    backup|backups)
      TWPR_cmd_backup "$@"
      ;;
    docker)
      TWPR_cmd_docker "$@"
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
