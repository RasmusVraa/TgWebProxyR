#!/usr/bin/env bash
# TgWebProxyR — Telegram bot install / control

TWPR_BOT_DIR="${TWPR_BOT_DIR:-${TWPR_ROOT}/bot}"
TWPR_BOT_ENV="${TWPR_STATE_DIR}/bot.env"
TWPR_BOT_UNIT="/etc/systemd/system/tgwebproxyr-bot.service"

TWPR_cmd_bot() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    ""|status) TWPR_bot_status ;;
    setup|install) TWPR_bot_setup "$@" ;;
    start) systemctl enable --now tgwebproxyr-bot.service; TWPR_bot_status ;;
    stop) systemctl stop tgwebproxyr-bot.service; TWPR_ok "бот остановлен" ;;
    restart) systemctl restart tgwebproxyr-bot.service; TWPR_bot_status ;;
    logs) journalctl -u tgwebproxyr-bot -n "${1:-80}" --no-pager ;;
    *)
      echo "  tgwebproxyr bot setup|status|start|stop|restart|logs"
      ;;
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
    TWPR_warn "не настроен — tgwebproxyr bot setup"
  fi
  local st
  st="$(TWPR_service_state tgwebproxyr-bot)"
  case "$st" in
    active) TWPR_ok "service: active" ;;
    inactive) TWPR_warn "service: inactive" ;;
    *) TWPR_warn "service: ${st}" ;;
  esac
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
  echo "  2) Напишите боту /chatid (после запуска) или узнайте id у @userinfobot"
  echo ""

  local token chats
  TWPR_ask token "Bot token"
  TWPR_ask chats "Allowed chat ids (через запятую)" "${TWPR_BOT_ALLOWED:-}"

  mkdir -p "$TWPR_STATE_DIR" /opt/tgwebproxyr/backups
  umask 077
  cat >"$TWPR_BOT_ENV" <<EOF
BOT_TOKEN=${token}
ALLOWED_CHAT_IDS=${chats}
EOF
  chmod 600 "$TWPR_BOT_ENV"
  umask 022

  # install bot files into /opt
  mkdir -p /opt/tgwebproxyr/bot
  cp -a "${TWPR_BOT_DIR}/twpr_bot.py" /opt/tgwebproxyr/bot/twpr_bot.py
  chmod 755 /opt/tgwebproxyr/bot/twpr_bot.py

  install -m 0644 "${TWPR_BOT_DIR}/twpr_bot.service" "$TWPR_BOT_UNIT"
  systemctl daemon-reload
  systemctl enable --now tgwebproxyr-bot.service

  TWPR_ok "Бот установлен и запущен"
  TWPR_info "Напишите боту /start"
  TWPR_info "Если доступа нет — /chatid и добавьте id в bot.env, затем: tgwebproxyr bot restart"
  TWPR_bot_status
}
