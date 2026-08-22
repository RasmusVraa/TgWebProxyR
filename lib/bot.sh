#!/usr/bin/env bash
# TgWebProxyR — Telegram bot install / control

TWPR_BOT_DIR="${TWPR_BOT_DIR:-${TWPR_ROOT}/bot}"
TWPR_BOT_ENV="${TWPR_STATE_DIR}/bot.env"
TWPR_BOT_UNIT="/etc/systemd/system/tgwebproxyr-bot.service"
TWPR_BOT_REPO_RAW="${TWPR_BOT_REPO_RAW:-https://raw.githubusercontent.com/${TWPR_GITHUB_REPO:-RasmusVraa/TgWebProxyR}/main}"

TWPR_cmd_bot() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    ""|menu) TWPR_bot_menu ;;
    status) TWPR_bot_status ;;
    setup|install) TWPR_bot_setup "$@" ;;
    update|upgrade) TWPR_bot_update "$@" ;;
    start) systemctl enable --now tgwebproxyr-bot.service; TWPR_bot_status ;;
    stop) systemctl stop tgwebproxyr-bot.service; TWPR_ok "бот остановлен" ;;
    restart) systemctl restart tgwebproxyr-bot.service; TWPR_bot_status ;;
    logs) journalctl -u tgwebproxyr-bot -n "${1:-80}" --no-pager ;;
    *)
      echo "  tgwebproxyr bot menu|setup|update|status|start|stop|restart|logs"
      ;;
  esac
}

TWPR_bot_menu() {
  TWPR_load_state
  echo ""
  echo -e "  ${C_BOLD}Telegram-бот${C_RESET}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
  TWPR_bot_status
  echo ""
  echo -e "  ${C_BOLD}1${C_RESET})  Настроить / переустановить (token + chat id)"
  echo -e "  ${C_BOLD}2${C_RESET})  Обновить бота (код с GitHub, token не трогаем)"
  echo -e "  ${C_BOLD}3${C_RESET})  Статус"
  echo -e "  ${C_BOLD}4${C_RESET})  Перезапуск"
  echo -e "  ${C_BOLD}5${C_RESET})  Логи"
  echo -e "  ${C_BOLD}6${C_RESET})  Остановить"
  echo -e "  ${C_BOLD}0${C_RESET})  Назад"
  echo ""
  local choice=""
  TWPR_ask choice "Выберите" "2"
  case "$choice" in
    1) TWPR_bot_setup ;;
    2) TWPR_bot_update ;;
    3) TWPR_bot_status ;;
    4) systemctl restart tgwebproxyr-bot.service 2>/dev/null; TWPR_bot_status ;;
    5) journalctl -u tgwebproxyr-bot -n 80 --no-pager; ;;
    6) systemctl stop tgwebproxyr-bot.service 2>/dev/null; TWPR_ok "бот остановлен" ;;
    0|*) return 0 ;;
  esac
}

TWPR_bot_status() {
  TWPR_load_state
  echo ""
  echo -e "  ${C_BOLD}Telegram-бот${C_RESET}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
  if [[ -f "$TWPR_BOT_ENV" ]]; then
    TWPR_ok "config: ${TWPR_BOT_ENV}"
  else
    TWPR_warn "не настроен — пункт «Настроить» или: tgwebproxyr bot setup"
  fi
  local st
  st="$(TWPR_service_state tgwebproxyr-bot)"
  case "$st" in
    active) TWPR_ok "service: active" ;;
    inactive) TWPR_warn "service: inactive" ;;
    *) TWPR_warn "service: ${st}" ;;
  esac
}

TWPR_bot_install_files() {
  # обновляет код/unit из локального TWPR_BOT_DIR или с GitHub
  local src_py="${TWPR_BOT_DIR}/twpr_bot.py"
  local src_unit="${TWPR_BOT_DIR}/twpr_bot.service"
  local dest_dir="/opt/tgwebproxyr/bot"
  mkdir -p "$dest_dir"

  if [[ ! -f "$src_py" ]] || [[ "${1:-}" == "--pull" ]]; then
    TWPR_info "Скачиваю twpr_bot.py с GitHub…"
    curl -fsSL --retry 4 --retry-delay 2 \
      "${TWPR_BOT_REPO_RAW}/bot/twpr_bot.py" \
      -o "${dest_dir}/twpr_bot.py.new"
    mv -f "${dest_dir}/twpr_bot.py.new" "${dest_dir}/twpr_bot.py"
    curl -fsSL --retry 4 --retry-delay 2 \
      "${TWPR_BOT_REPO_RAW}/bot/twpr_bot.service" \
      -o "${dest_dir}/twpr_bot.service.new" 2>/dev/null \
      && mv -f "${dest_dir}/twpr_bot.service.new" "${dest_dir}/twpr_bot.service" || true
  else
    if [[ "$src_py" -ef "${dest_dir}/twpr_bot.py" ]]; then
      :
    else
      cp -a "$src_py" "${dest_dir}/twpr_bot.py"
    fi
    if [[ -f "$src_unit" ]] && [[ ! "$src_unit" -ef "${dest_dir}/twpr_bot.service" ]]; then
      cp -a "$src_unit" "${dest_dir}/twpr_bot.service"
    fi
  fi

  chmod 755 "${dest_dir}/twpr_bot.py"
  if [[ -f "${dest_dir}/twpr_bot.service" ]]; then
    install -m 0644 "${dest_dir}/twpr_bot.service" "$TWPR_BOT_UNIT"
  elif [[ -f "$src_unit" ]]; then
    install -m 0644 "$src_unit" "$TWPR_BOT_UNIT"
  fi
  systemctl daemon-reload 2>/dev/null || true
}

TWPR_bot_update() {
  TWPR_require_root
  TWPR_banner
  echo "  Обновление Telegram-бота"
  echo "  Token / chat id в ${TWPR_BOT_ENV} не меняются"
  echo ""

  if [[ ! -f "$TWPR_BOT_ENV" ]]; then
    TWPR_warn "Бот ещё не настроен"
    TWPR_ask_yn _go "Сейчас пройти setup" "Y"
    [[ "${_go:-}" == "yes" ]] && TWPR_bot_setup
    return
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    TWPR_err "нужен python3"
    return 1
  fi

  # подтянуть свежий менеджер/бота в /opt, если есть сеть
  TWPR_bot_install_files --pull

  systemctl enable tgwebproxyr-bot.service 2>/dev/null || true
  systemctl restart tgwebproxyr-bot.service
  sleep 1
  TWPR_ok "Бот обновлён и перезапущен"
  TWPR_bot_status
}

TWPR_bot_setup() {
  TWPR_require_root
  TWPR_banner
  TWPR_step 1 3 "Telegram bot"

  if ! command -v python3 >/dev/null 2>&1; then
    TWPR_ensure_deps
    if command -v apt-get >/dev/null 2>&1; then
      apt-get install -y -qq python3
    fi
  fi
  command -v python3 >/dev/null 2>&1 || { TWPR_err "нужен python3"; return 1; }

  echo "  1) Создайте бота у @BotFather → /newbot → получите token"
  echo "  2) Chat id = ваш Telegram user id (число)"
  echo "     узнать: @userinfobot или напишите боту /chatid после старта"
  echo "     для лички достаточно одного id, группам — id группы (часто отрицательный)"
  echo ""

  local token chats
  # подтянуть старые значения из bot.env
  if [[ -f "$TWPR_BOT_ENV" ]]; then
    # shellcheck disable=SC1090
    set -a
    # shellcheck disable=SC1091
    source "$TWPR_BOT_ENV" 2>/dev/null || true
    set +a
  fi
  TWPR_ask token "Bot token" "${BOT_TOKEN:-}"
  TWPR_ask chats "Ваш user/chat id" "${ALLOWED_CHAT_IDS:-${TWPR_BOT_ALLOWED:-}}"

  mkdir -p "$TWPR_STATE_DIR" /opt/tgwebproxyr/backups
  umask 077
  cat >"$TWPR_BOT_ENV" <<EOF
BOT_TOKEN=${token}
ALLOWED_CHAT_IDS=${chats}
EOF
  chmod 600 "$TWPR_BOT_ENV"
  umask 022

  TWPR_bot_install_files
  systemctl enable --now tgwebproxyr-bot.service

  TWPR_ok "Бот установлен и запущен"
  TWPR_info "Напишите боту /start"
  TWPR_info "Если ⛔ — /chatid и добавьте число в ${TWPR_BOT_ENV}, затем: tgwebproxyr bot restart"
  TWPR_bot_status
}
