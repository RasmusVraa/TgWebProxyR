#!/usr/bin/env bash
# TgWebProxyR — Telegram bot (логика pairing как у MTProxyL)

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
      echo "  tgwebproxyr bot  → меню"
      echo "  tgwebproxyr bot setup|update|status|start|stop|restart|logs"
      ;;
  esac
}

TWPR_bot_menu() {
  TWPR_load_state
  clear 2>/dev/null || true
  TWPR_banner
  TWPR_bot_status
  echo ""
  echo -e "  ${C_BOLD}1${C_RESET})  Настроить   ${C_DIM}(token → /start в Telegram)${C_RESET}"
  echo -e "  ${C_BOLD}2${C_RESET})  Обновить код бота"
  echo -e "  ${C_BOLD}3${C_RESET})  Перезапуск"
  echo -e "  ${C_BOLD}4${C_RESET})  Логи"
  echo -e "  ${C_BOLD}5${C_RESET})  Стоп"
  echo -e "  ${C_BOLD}0${C_RESET})  Назад"
  echo ""
  local choice=""
  TWPR_ask choice "Пункт" "1"
  case "$choice" in
    1) TWPR_bot_setup ;;
    2) TWPR_bot_update ;;
    3) systemctl restart tgwebproxyr-bot.service 2>/dev/null; TWPR_bot_status ;;
    4) journalctl -u tgwebproxyr-bot -n 60 --no-pager ;;
    5) systemctl stop tgwebproxyr-bot.service 2>/dev/null; TWPR_ok "остановлен" ;;
    *) return 0 ;;
  esac
}

TWPR_bot_status() {
  TWPR_load_state
  echo ""
  echo -e "  ${C_BOLD}Telegram-бот${C_RESET}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
  if [[ -f "$TWPR_BOT_ENV" ]]; then
    # shellcheck disable=SC1090
    set -a; source "$TWPR_BOT_ENV" 2>/dev/null || true; set +a
    local masked="—"
    if [[ -n "${BOT_TOKEN:-}" && ${#BOT_TOKEN} -gt 12 ]]; then
      masked="${BOT_TOKEN:0:6}…${BOT_TOKEN: -4}"
    fi
    TWPR_ok "token  ${masked}"
    TWPR_ok "admin  ${ALLOWED_CHAT_IDS:-—}"
  else
    TWPR_warn "не настроен"
  fi
  local st
  st="$(TWPR_service_state tgwebproxyr-bot)"
  case "$st" in
    active) TWPR_ok "service active" ;;
    *) TWPR_warn "service ${st}" ;;
  esac
}

TWPR_bot_tg_api() {
  # TWPR_bot_tg_api TOKEN METHOD [query]
  local tok="$1" method="$2" q="${3:-}"
  curl -fsS --max-time 20 \
    "https://api.telegram.org/bot${tok}/${method}${q:+?$q}" 2>/dev/null || true
}

TWPR_bot_validate_token() {
  local tok="$1" resp
  resp="$(TWPR_bot_tg_api "$tok" getMe)"
  echo "$resp" | grep -q '"ok":true'
}

# Как MTProxyL: ждём первое сообщение → берём from.id
TWPR_bot_wait_admin() {
  local tok="$1"
  local deadline resp id name offset=""
  echo ""
  echo -e "  ${C_BOLD}Откройте бота в Telegram и отправьте /start${C_RESET}"
  echo -e "  ${C_DIM}Ждём до 90 секунд — chat id подхватится сам${C_RESET}"
  echo ""

  TWPR_bot_tg_api "$tok" "deleteWebhook" "drop_pending_updates=true" >/dev/null
  # сбросить очередь
  resp="$(TWPR_bot_tg_api "$tok" getUpdates "timeout=0&limit=100")"
  offset="$(echo "$resp" | grep -oE '"update_id":[0-9]+' | tail -1 | cut -d: -f2 || true)"
  if [[ -n "$offset" ]]; then
    offset=$((offset + 1))
  fi

  deadline=$(( $(date +%s) + 90 ))
  echo -n "  ожидание" >&2
  while [[ "$(date +%s)" -lt "$deadline" ]]; do
    if [[ -n "$offset" ]]; then
      resp="$(TWPR_bot_tg_api "$tok" getUpdates "timeout=8&limit=5&offset=${offset}")"
    else
      resp="$(TWPR_bot_tg_api "$tok" getUpdates "timeout=8&limit=5")"
    fi
    id="$(echo "$resp" | grep -oE '"from":\{[^}]*"id":[-0-9]+' | head -1 | grep -oE 'id":[-0-9]+' | head -1 | cut -d: -f2 || true)"
    if [[ -z "$id" ]]; then
      id="$(echo "$resp" | python3 -c '
import sys,json
try:
  d=json.load(sys.stdin)
  for u in d.get("result") or []:
    m=u.get("message") or u.get("edited_message") or {}
    f=m.get("from") or {}
    if f.get("id") is not None:
      print(f["id"]); break
except Exception:
  pass
' 2>/dev/null || true)"
    fi
    # advance offset
    local last
    last="$(echo "$resp" | grep -oE '"update_id":[0-9]+' | tail -1 | cut -d: -f2 || true)"
    [[ -n "$last" ]] && offset=$((last + 1))

    if [[ -n "$id" ]]; then
      echo "" >&2
      TWPR_ok "Админ подхвачен: ${id}" >&2
      printf '%s' "$id"
      return 0
    fi
    echo -n "." >&2
  done
  echo "" >&2
  TWPR_warn "Не дождались /start" >&2
  local manual=""
  local __in
  __in="$(TWPR_stdin)"
  read -r -p "  Введите chat id вручную (Enter — отмена): " manual <"$__in" || true
  manual="$(echo "$manual" | tr -d '[:space:]')"
  if [[ -n "$manual" && "$manual" =~ ^-?[0-9]+$ ]]; then
    printf '%s' "$manual"
    return 0
  fi
  return 1
}

TWPR_bot_install_files() {
  local dest_dir="/opt/tgwebproxyr/bot"
  mkdir -p "$dest_dir"
  if [[ "${1:-}" == "--pull" ]] || [[ ! -f "${TWPR_BOT_DIR}/twpr_bot.py" ]]; then
    TWPR_info "Скачиваю бота с GitHub…"
    curl -fsSL --retry 4 --retry-delay 1 \
      "${TWPR_BOT_REPO_RAW}/bot/twpr_bot.py" -o "${dest_dir}/twpr_bot.py.new"
    mv -f "${dest_dir}/twpr_bot.py.new" "${dest_dir}/twpr_bot.py"
    curl -fsSL --retry 2 \
      "${TWPR_BOT_REPO_RAW}/bot/twpr_bot.service" -o "${dest_dir}/twpr_bot.service" 2>/dev/null || true
  else
    if [[ ! "${TWPR_BOT_DIR}/twpr_bot.py" -ef "${dest_dir}/twpr_bot.py" ]]; then
      cp -a "${TWPR_BOT_DIR}/twpr_bot.py" "${dest_dir}/twpr_bot.py"
    fi
    [[ -f "${TWPR_BOT_DIR}/twpr_bot.service" ]] \
      && cp -a "${TWPR_BOT_DIR}/twpr_bot.service" "${dest_dir}/twpr_bot.service" 2>/dev/null || true
  fi
  chmod 755 "${dest_dir}/twpr_bot.py"
  local unit_src="${dest_dir}/twpr_bot.service"
  [[ -f "${TWPR_BOT_DIR}/twpr_bot.service" ]] && unit_src="${TWPR_BOT_DIR}/twpr_bot.service"
  [[ -f "$unit_src" ]] && install -m 0644 "$unit_src" "$TWPR_BOT_UNIT"
  systemctl daemon-reload 2>/dev/null || true
}

TWPR_bot_setup() {
  TWPR_require_root
  clear 2>/dev/null || true
  TWPR_banner
  echo -e "  ${C_BOLD}Настройка Telegram-бота${C_RESET}"
  echo -e "  ${C_DIM}Как в ProxyL: только token → вы пишете /start → id сам${C_RESET}"
  echo ""

  if ! command -v python3 >/dev/null 2>&1; then
    command -v apt-get >/dev/null 2>&1 && apt-get install -y -qq python3 curl
  fi
  command -v python3 >/dev/null 2>&1 || { TWPR_err "нужен python3"; return 1; }
  command -v curl >/dev/null 2>&1 || { TWPR_err "нужен curl"; return 1; }

  echo "  1) @BotFather → /newbot → скопируйте token"
  echo "  2) После ввода token откройте бота и нажмите Start /start"
  echo ""

  local token="" admin=""
  while true; do
    TWPR_ask token "Bot token"
    token="$(echo "$token" | tr -d '[:space:]')"
    if TWPR_bot_validate_token "$token"; then
      TWPR_ok "token OK"
      break
    fi
    TWPR_warn "Неверный token — попробуйте ещё"
  done

  admin="$(TWPR_bot_wait_admin "$token")" || {
    TWPR_err "Админ не определён — setup отменён"
    return 1
  }

  mkdir -p "$TWPR_STATE_DIR"
  umask 077
  cat >"$TWPR_BOT_ENV" <<EOF
BOT_TOKEN=${token}
ALLOWED_CHAT_IDS=${admin}
EOF
  chmod 600 "$TWPR_BOT_ENV"
  umask 022

  TWPR_bot_install_files
  systemctl enable --now tgwebproxyr-bot.service
  sleep 1
  TWPR_ok "Бот запущен. Напишите ему /start ещё раз — откроется меню."
  TWPR_bot_status
}

TWPR_bot_update() {
  TWPR_require_root
  TWPR_banner
  if [[ ! -f "$TWPR_BOT_ENV" ]]; then
    TWPR_warn "Сначала setup"
    TWPR_bot_setup
    return
  fi
  TWPR_bot_install_files --pull
  systemctl restart tgwebproxyr-bot.service
  TWPR_ok "Бот обновлён"
  TWPR_bot_status
}
