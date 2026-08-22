#!/usr/bin/env bash
# TgWebProxyR — интерактивное меню в духе MTProxyL / ProxyL

TWPR_menu_header() {
  clear 2>/dev/null || true
  TWPR_banner
  TWPR_load_state
  local mode="—"
  if TWPR_is_configured; then
    if TWPR_is_docker; then
      mode="Docker"
    else
      mode="Native"
    fi
    # без health-probe — меню должно открываться мгновенно
    echo -e "  ${C_BOLD}${TWPR_HOSTNAME:-?}${C_RESET}  ·  ${mode}"
  else
    echo -e "  ${C_YELLOW}ещё не установлено${C_RESET}"
  fi
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
  echo ""
}

TWPR_dashboard() {
  while true; do
    TWPR_menu_header
    echo -e "  ${C_BOLD}1${C_RESET})  Ссылки"
    echo -e "  ${C_BOLD}2${C_RESET})  Статус"
    echo -e "  ${C_BOLD}3${C_RESET})  Проверка работоспособности"
    echo -e "  ${C_BOLD}4${C_RESET})  Управление   ${C_DIM}start / stop / restart${C_RESET}"
    echo -e "  ${C_BOLD}5${C_RESET})  Логи"
    echo -e "  ${C_BOLD}6${C_RESET})  Пользователи / secrets"
    echo -e "  ${C_BOLD}7${C_RESET})  Настройки"
    echo -e "  ${C_BOLD}8${C_RESET})  Telegram-бот"
    echo -e "  ${C_BOLD}9${C_RESET})  Обновление и бэкапы"
    echo -e "  ${C_BOLD}i${C_RESET})  Установка / переустановка"
    echo -e "  ${C_BOLD}u${C_RESET})  Удалить"
    echo -e "  ${C_BOLD}0${C_RESET})  Выход"
    echo ""
    local choice=""
    read -r -p "  › " choice <"$(TWPR_stdin)" || true
    case "$choice" in
      1) TWPR_cmd_link; TWPR_pause ;;
      2) TWPR_cmd_status; TWPR_pause ;;
      3|h|H) TWPR_cmd_health; TWPR_pause ;;
      4) TWPR_menu_control ;;
      5) TWPR_menu_logs ;;
      6) TWPR_menu_secrets ;;
      7) TWPR_menu_settings ;;
      8) TWPR_bot_menu; TWPR_pause ;;
      9) TWPR_menu_ops ;;
      i|I) TWPR_menu_install ;;
      u|U) TWPR_cmd_uninstall ;;
      0|q|Q) exit 0 ;;
      *) ;;
    esac
  done
}

TWPR_menu_control() {
  while true; do
    TWPR_menu_header
    echo -e "  ${C_BOLD}Управление сервисом${C_RESET}"
    echo ""
    echo -e "  ${C_BOLD}1${C_RESET})  Старт"
    echo -e "  ${C_BOLD}2${C_RESET})  Стоп"
    echo -e "  ${C_BOLD}3${C_RESET})  Рестарт"
    echo -e "  ${C_BOLD}4${C_RESET})  Doctor / починить"
    echo -e "  ${C_BOLD}0${C_RESET})  Назад"
    echo ""
    local choice=""
    TWPR_ask choice "Пункт" "0"
    case "$choice" in
      1) TWPR_cmd_start; TWPR_pause ;;
      2) TWPR_cmd_stop; TWPR_pause ;;
      3) TWPR_cmd_restart; TWPR_pause ;;
      4) TWPR_cmd_doctor; TWPR_pause ;;
      0|*) return 0 ;;
    esac
  done
}

TWPR_menu_logs() {
  TWPR_menu_header
  echo -e "  ${C_BOLD}Логи${C_RESET}"
  echo ""
  if TWPR_is_docker; then
    echo -e "  ${C_BOLD}1${C_RESET})  Все контейнеры"
    echo -e "  ${C_BOLD}2${C_RESET})  relay"
    echo -e "  ${C_BOLD}3${C_RESET})  mtproxy"
    echo -e "  ${C_BOLD}4${C_RESET})  caddy"
  else
    echo -e "  ${C_BOLD}1${C_RESET})  tproxy-server + mtproxy + caddy"
    echo -e "  ${C_BOLD}2${C_RESET})  только tproxy-server"
    echo -e "  ${C_BOLD}3${C_RESET})  только mtproxy"
    echo -e "  ${C_BOLD}4${C_RESET})  только caddy"
  fi
  echo -e "  ${C_BOLD}0${C_RESET})  Назад"
  echo ""
  local choice=""
  TWPR_ask choice "Пункт" "1"
  case "$choice" in
    1)
      if TWPR_is_docker; then TWPR_cmd_logs "" 100; else TWPR_cmd_logs tproxy-server 100; fi
      TWPR_pause
      ;;
    2)
      if TWPR_is_docker; then TWPR_cmd_logs relay 100; else TWPR_cmd_logs tproxy-server 100; fi
      TWPR_pause
      ;;
    3)
      if TWPR_is_docker; then TWPR_cmd_logs mtproxy 100; else TWPR_cmd_logs mtproxy 100; fi
      TWPR_pause
      ;;
    4)
      if TWPR_is_docker; then TWPR_cmd_logs caddy 100; else TWPR_cmd_logs caddy 100; fi
      TWPR_pause
      ;;
    *) return 0 ;;
  esac
}

TWPR_menu_secrets() {
  while true; do
    TWPR_menu_header
    echo -e "  ${C_BOLD}Пользователи / secrets${C_RESET}"
    echo ""
    TWPR_cmd_secret_list 2>/dev/null || true
    echo ""
    echo -e "  ${C_BOLD}1${C_RESET})  Показать ссылки"
    echo -e "  ${C_BOLD}2${C_RESET})  Показать secret"
    echo -e "  ${C_BOLD}3${C_RESET})  Сменить (rotate) secret"
    echo -e "  ${C_BOLD}4${C_RESET})  Добавить профиль ${C_DIM}(native)${C_RESET}"
    echo -e "  ${C_BOLD}5${C_RESET})  Удалить профиль ${C_DIM}(native)${C_RESET}"
    echo -e "  ${C_BOLD}0${C_RESET})  Назад"
    echo ""
    local choice=""
    TWPR_ask choice "Пункт" "0"
    case "$choice" in
      1) TWPR_cmd_link; TWPR_pause ;;
      2) TWPR_cmd_secret_show; TWPR_pause ;;
      3) TWPR_cmd_secret_rotate; TWPR_pause ;;
      4) TWPR_cmd_secret_add; TWPR_pause ;;
      5) TWPR_cmd_secret_remove; TWPR_pause ;;
      0|*) return 0 ;;
    esac
  done
}

TWPR_menu_settings() {
  TWPR_menu_header
  echo -e "  ${C_BOLD}Настройки${C_RESET}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
  TWPR_load_state
  TWPR_info "hostname   ${TWPR_HOSTNAME:-—}"
  TWPR_info "email      ${TWPR_EMAIL:-—}"
  TWPR_info "режим      ${TWPR_DEPLOY_MODE:-—}"
  TWPR_info "workers    ${TWPR_MTPROXY_WORKERS:-1}"
  TWPR_info "maxconn    ${TWPR_MTPROXY_MAX_CONNECTIONS:-4096}"
  TWPR_info "HTTP/HTTPS ${TWPR_PORT_HTTP:-80}/${TWPR_PORT_HTTPS:-443}"
  TWPR_info "сайт       ${TWPR_SITE_DIR}"
  TWPR_info "state      ${TWPR_STATE_DIR}/settings.env"
  if TWPR_is_docker; then
    TWPR_info "compose    ${TWPR_ROOT}/docker/.env"
  fi
  echo ""
  echo -e "  ${C_BOLD}1${C_RESET})  Открыть settings.env в редакторе"
  echo -e "  ${C_BOLD}2${C_RESET})  Сменить workers (нужен рестарт)"
  echo -e "  ${C_BOLD}0${C_RESET})  Назад"
  echo ""
  local choice=""
  TWPR_ask choice "Пункт" "0"
  case "$choice" in
    1)
      ${EDITOR:-nano} "${TWPR_STATE_DIR}/settings.env"
      TWPR_load_state
      TWPR_pause
      ;;
    2)
      local w=""
      TWPR_ask w "MTProxy workers" "${TWPR_MTPROXY_WORKERS:-1}"
      TWPR_MTPROXY_WORKERS="$w"
      TWPR_save_state
      if TWPR_is_docker; then
        TWPR_docker_write_env
        TWPR_docker_compose up -d --force-recreate mtproxy 2>/dev/null || TWPR_cmd_restart
      else
        if [[ -f /etc/mtproxy/mtproxy.env ]]; then
          sed -i "s/^MTPROXY_WORKERS=.*/MTPROXY_WORKERS=${w}/" /etc/mtproxy/mtproxy.env || true
        fi
        TWPR_cmd_restart
      fi
      TWPR_pause
      ;;
    *) return 0 ;;
  esac
}

TWPR_menu_ops() {
  while true; do
    TWPR_menu_header
    echo -e "  ${C_BOLD}Обновление и бэкапы${C_RESET}"
    echo ""
    echo -e "  ${C_BOLD}1${C_RESET})  Обновить стек / образы"
    echo -e "  ${C_BOLD}2${C_RESET})  Создать бэкап ${C_DIM}(+ отправка админу)${C_RESET}"
    echo -e "  ${C_BOLD}3${C_RESET})  Список бэкапов"
    echo -e "  ${C_BOLD}4${C_RESET})  Восстановить бэкап"
    echo -e "  ${C_BOLD}5${C_RESET})  Автобэкап ${C_DIM}hourly/daily/monthly${C_RESET}"
    echo -e "  ${C_BOLD}0${C_RESET})  Назад"
    echo ""
    local choice="" name=""
    TWPR_ask choice "Пункт" "0"
    case "$choice" in
      1) TWPR_cmd_update; TWPR_pause ;;
      2) TWPR_backup_create; TWPR_pause ;;
      3) TWPR_backup_list; TWPR_pause ;;
      4)
        TWPR_backup_list
        TWPR_ask name "Имя файла (twpr-….tar.gz)"
        TWPR_backup_restore "$name"
        TWPR_pause
        ;;
      5)
        TWPR_cmd_autobackup status
        echo ""
        echo -e "  ${C_BOLD}1${C_RESET}) hourly  ${C_BOLD}2${C_RESET}) daily  ${C_BOLD}3${C_RESET}) monthly  ${C_BOLD}4${C_RESET}) off"
        TWPR_ask choice "Период" "2"
        case "$choice" in
          1) TWPR_cmd_autobackup hourly ;;
          2) TWPR_cmd_autobackup daily ;;
          3) TWPR_cmd_autobackup monthly ;;
          4) TWPR_cmd_autobackup off ;;
        esac
        TWPR_pause
        ;;
      0|*) return 0 ;;
    esac
  done
}

TWPR_menu_install() {
  TWPR_menu_header
  echo -e "  ${C_BOLD}Установка${C_RESET}"
  echo ""
  echo -e "  ${C_BOLD}1${C_RESET})  Мастер (выбор режима)"
  echo -e "  ${C_BOLD}2${C_RESET})  Быстро · Docker"
  echo -e "  ${C_BOLD}3${C_RESET})  Docker · расширенно"
  echo -e "  ${C_BOLD}4${C_RESET})  Native · быстро"
  echo -e "  ${C_BOLD}5${C_RESET})  Native · расширенно"
  echo -e "  ${C_BOLD}0${C_RESET})  Назад"
  echo ""
  local choice=""
  TWPR_ask choice "Пункт" "0"
  case "$choice" in
    1) unset TWPR_SETUP_MODE; TWPR_cmd_setup; TWPR_pause ;;
    2) export TWPR_SETUP_MODE=docker TWPR_SETUP_DEPTH=quick; TWPR_cmd_setup; TWPR_pause ;;
    3) export TWPR_SETUP_MODE=docker TWPR_SETUP_DEPTH=advanced; TWPR_cmd_setup; TWPR_pause ;;
    4) export TWPR_SETUP_MODE=native TWPR_SETUP_DEPTH=quick; TWPR_cmd_setup; TWPR_pause ;;
    5) export TWPR_SETUP_MODE=native TWPR_SETUP_DEPTH=advanced; TWPR_cmd_setup; TWPR_pause ;;
    *) return 0 ;;
  esac
}
