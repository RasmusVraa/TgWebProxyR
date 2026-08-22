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
source "${TWPR_ROOT}/lib/certs.sh"
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
source "${TWPR_ROOT}/lib/api.sh"
# shellcheck disable=SC1091
source "${TWPR_ROOT}/lib/quota.sh"
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

  ${C_BOLD}Secrets / пользователи${C_RESET}
  tgwebproxyr secret list|show|link [name]
  tgwebproxyr secret rotate [name]
  tgwebproxyr secret add [name]
  tgwebproxyr secret rename <old> <new>
  tgwebproxyr secret remove <name>
  tgwebproxyr secret apply
  tgwebproxyr secret quota <name> <10G|unlimited>
  tgwebproxyr secret enable|disable <name>
  tgwebproxyr secret reset-usage <name|all>
  tgwebproxyr quota check|status     # enforce лимитов трафика
  tgwebproxyr metrics             трафик (relay /metrics)

  ${C_BOLD}Прочее${C_RESET}
  tgwebproxyr bot …           setup|update|menu|…
  tgwebproxyr api …           setup|token|status  (Shop API)
  tgwebproxyr certs …         status|detect       (TLS / ACME)
  tgwebproxyr site …          list|status|set|random  (шаблон публичного сайта)
  tgwebproxyr backup …        create|list|restore|auto
  tgwebproxyr docker …        setup|up|down|logs|pull
  tgwebproxyr update              # менеджер с GitHub + стек
  tgwebproxyr update --stack-only # только образы/engine (без скачивания скрипта)
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
    update) TWPR_cmd_update "$@" ;;
    doctor|fix|repair) TWPR_cmd_doctor ;;
    secret)
      case "${1:-}" in
        show) TWPR_cmd_secret_show ;;
        list|ls) TWPR_cmd_secret_list ;;
        link) shift || true; TWPR_cmd_secret_link "${1:-}" ;;
        rotate) shift || true; TWPR_cmd_secret_rotate "${1:-}" ;;
        add) shift || true; TWPR_cmd_secret_add "${1:-}" ;;
        rename|mv) shift || true; TWPR_cmd_secret_rename "${1:-}" "${2:-}" ;;
        remove|rm|del) shift || true; TWPR_cmd_secret_remove "${1:-}" ;;
        apply|sync) TWPR_cmd_secret_apply ;;
        quota|limit) shift || true; TWPR_cmd_secret_quota "${1:-}" "${2:-}" ;;
        enable|on) shift || true; TWPR_cmd_secret_enable "${1:-}" 1 ;;
        disable|off) shift || true; TWPR_cmd_secret_enable "${1:-}" 0 ;;
        reset-usage|reset_usage) shift || true; TWPR_cmd_secret_reset_usage "${1:-}" ;;
        ""|menu) TWPR_menu_secrets ;;
        *) TWPR_err "secret: list|show|link|rotate|add|rename|remove|apply|quota|enable|disable|reset-usage"; exit 2 ;;
      esac
      ;;
    quota|quotas) TWPR_cmd_quota "$@" ;;
    metrics|traffic) TWPR_cmd_metrics "$@" ;;
    bot) TWPR_cmd_bot "$@" ;;
    api) TWPR_cmd_api "$@" ;;
    certs|cert|tls) TWPR_cmd_certs "$@" ;;
    site|sites|theme|themes) TWPR_cmd_site "$@" ;;
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
