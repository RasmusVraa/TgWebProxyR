#!/usr/bin/env bash
# TgWebProxyR — бэкапы, автобэкап, отправка админу в Telegram

TWPR_BACKUP_DIR="${TWPR_BACKUP_DIR:-/opt/tgwebproxyr/backups}"
TWPR_AUTOBACKUP_ENV="${TWPR_STATE_DIR}/autobackup.env"
TWPR_AUTOBACKUP_UNIT="/etc/systemd/system/tgwebproxyr-autobackup.service"
TWPR_AUTOBACKUP_TIMER="/etc/systemd/system/tgwebproxyr-autobackup.timer"

TWPR_cmd_backup() {
  local sub="${1:-create}"
  shift || true
  case "$sub" in
    create|new) TWPR_backup_create "$@" ;;
    list) TWPR_backup_list ;;
    restore) TWPR_backup_restore "${1:-}" "${2:-}" ;;
    auto|autobackup) TWPR_cmd_autobackup "$@" ;;
    send) TWPR_backup_send_tg "${1:-}" ;;
    *)
      echo "  tgwebproxyr backup create|list|restore <name> [--yes]"
      echo "  tgwebproxyr backup auto status|off|hourly|daily|monthly"
      echo "  tgwebproxyr backup send <name>"
      ;;
  esac
}

TWPR_autobackup_load() {
  TWPR_AUTOBACKUP="${TWPR_AUTOBACKUP:-off}"
  TWPR_AUTOBACKUP_SEND="${TWPR_AUTOBACKUP_SEND:-1}"
  TWPR_AUTOBACKUP_KEEP="${TWPR_AUTOBACKUP_KEEP:-12}"
  if [[ -f "$TWPR_AUTOBACKUP_ENV" ]]; then
    # shellcheck disable=SC1090
    set -a
    # shellcheck disable=SC1091
    source "$TWPR_AUTOBACKUP_ENV"
    set +a
  fi
}

TWPR_autobackup_save() {
  mkdir -p "$TWPR_STATE_DIR"
  umask 077
  cat >"$TWPR_AUTOBACKUP_ENV" <<EOF
TWPR_AUTOBACKUP=${TWPR_AUTOBACKUP:-off}
TWPR_AUTOBACKUP_SEND=${TWPR_AUTOBACKUP_SEND:-1}
TWPR_AUTOBACKUP_KEEP=${TWPR_AUTOBACKUP_KEEP:-12}
EOF
  chmod 600 "$TWPR_AUTOBACKUP_ENV"
}

TWPR_backup_prune() {
  TWPR_autobackup_load
  local keep="${TWPR_AUTOBACKUP_KEEP:-12}" i=0
  mkdir -p "$TWPR_BACKUP_DIR"
  # оставляем последние N архивов
  while IFS= read -r f; do
    i=$((i + 1))
    if (( i > keep )); then
      rm -f "$f"
      [[ -d "${f%.tar.gz}" ]] && rm -rf "${f%.tar.gz}"
    fi
  done < <(ls -1t "$TWPR_BACKUP_DIR"/twpr-*.tar.gz 2>/dev/null || true)
}

TWPR_backup_notify_tg() {
  # TWPR_backup_notify_tg ARCHIVE_PATH [caption]
  local archive="$1" caption="${2:-TgWebProxyR backup}"
  [[ -f "$archive" ]] || return 0
  TWPR_autobackup_load
  [[ "${TWPR_AUTOBACKUP_SEND:-1}" == "1" ]] || return 0

  local token="" chats=""
  if [[ -f "${TWPR_STATE_DIR}/bot.env" ]]; then
    # shellcheck disable=SC1090
    set -a
    # shellcheck disable=SC1091
    source "${TWPR_STATE_DIR}/bot.env"
    set +a
    token="${BOT_TOKEN:-}"
    chats="${ALLOWED_CHAT_IDS:-}"
  fi
  [[ -n "$token" && -n "$chats" ]] || return 0

  local chat
  IFS=',' read -ra _chats <<<"$chats"
  for chat in "${_chats[@]}"; do
    chat="$(echo "$chat" | tr -d '[:space:]')"
    [[ -n "$chat" ]] || continue
    curl -fsS --max-time 60 \
      -F "chat_id=${chat}" \
      -F "caption=${caption}" \
      -F "document=@${archive}" \
      "https://api.telegram.org/bot${token}/sendDocument" >/dev/null 2>&1 || true
  done
}

TWPR_backup_create() {
  TWPR_require_root
  TWPR_load_state 2>/dev/null || true
  mkdir -p "$TWPR_BACKUP_DIR"
  local stamp dest archive quiet=0
  for a in "$@"; do
    [[ "$a" == "--quiet" || "$a" == "-q" ]] && quiet=1
  done
  stamp="$(date -u +%Y%m%d-%H%M%S)"
  dest="${TWPR_BACKUP_DIR}/twpr-${stamp}"
  archive="${dest}.tar.gz"
  mkdir -p "$dest"

  for f in \
    /etc/tgwebproxyr/settings.env \
    /etc/tgwebproxyr/bot.env \
    /etc/tgwebproxyr/profiles.json \
    /etc/tgwebproxyr/autobackup.env; do
    [[ -f "$f" ]] && cp -a "$f" "$dest/"
  done
  [[ -f "${TWPR_ROOT}/docker/.env" ]] && cp -a "${TWPR_ROOT}/docker/.env" "$dest/docker.env"
  cat >"$dest/meta.json" <<EOF
{"created_at":"${stamp}","hostname":"${TWPR_HOSTNAME:-}","version":"${TWPR_VERSION:-}","mode":"${TWPR_DEPLOY_MODE:-}"}
EOF

  tar -czf "$archive" -C "$TWPR_BACKUP_DIR" "$(basename "$dest")" 2>/dev/null
  chmod 600 "$archive"
  rm -rf "$dest"

  TWPR_backup_prune
  [[ "$quiet" -eq 1 ]] || TWPR_ok "Бэкап: ${archive}"

  local host="${TWPR_HOSTNAME:-server}"
  TWPR_backup_notify_tg "$archive" "💾 TgWebProxyR backup · ${host} · ${stamp}"
  printf '%s\n' "$archive"
}

TWPR_backup_send_tg() {
  local name="$1" path=""
  [[ -n "$name" ]] || { TWPR_err "укажите имя бэкапа"; return 1; }
  path="${TWPR_BACKUP_DIR}/${name}"
  [[ -f "$path" ]] || path="${TWPR_BACKUP_DIR}/${name}.tar.gz"
  [[ -f "$path" ]] || path="$name"
  [[ -f "$path" ]] || { TWPR_err "нет файла: ${name}"; return 1; }
  TWPR_AUTOBACKUP_SEND=1
  TWPR_backup_notify_tg "$path" "💾 TgWebProxyR backup · $(basename "$path")"
  TWPR_ok "Отправлено админу"
}

TWPR_backup_list() {
  mkdir -p "$TWPR_BACKUP_DIR"
  echo ""
  echo -e "  ${C_BOLD}Бэкапы${C_RESET} → ${TWPR_BACKUP_DIR}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
  local f found=0
  for f in $(ls -1t "$TWPR_BACKUP_DIR"/twpr-*.tar.gz 2>/dev/null); do
    found=1
    TWPR_info "$(basename "$f")  $(( $(stat -c%s "$f" 2>/dev/null || echo 0) / 1024 ))K"
  done
  [[ "$found" -eq 1 ]] || TWPR_warn "пока пусто"
  TWPR_autobackup_load
  echo ""
  TWPR_info "автобэкап: ${TWPR_AUTOBACKUP:-off}  ·  sendTG=${TWPR_AUTOBACKUP_SEND:-1}"
}

TWPR_backup_restore() {
  TWPR_require_root
  local name="$1" yes="${2:-}"
  [[ -n "$name" ]] || { TWPR_err "укажите имя бэкапа"; return 1; }
  local archive="${TWPR_BACKUP_DIR}/${name}"
  [[ -f "$archive" ]] || archive="${TWPR_BACKUP_DIR}/${name}.tar.gz"
  [[ -f "$archive" ]] || archive="$name"
  [[ -f "$archive" ]] || { TWPR_err "нет бэкапа: ${name}"; return 1; }

  if [[ "$yes" != "--yes" && "$yes" != "-y" && "${TWPR_YES:-}" != "1" ]]; then
    TWPR_warn "Восстановление из $(basename "$archive")"
    local choice=""
    TWPR_ask_yn choice "Продолжить (текущие настройки будут перезаписаны)" "n"
    [[ "$choice" == "yes" ]] || return 0
  fi

  local tmp
  tmp="$(mktemp -d /tmp/twpr-restore.XXXXXX)"
  tar -xzf "$archive" -C "$tmp"
  local src
  src="$(find "$tmp" -maxdepth 1 -type d -name 'twpr-*' | head -1)"
  [[ -n "$src" ]] || src="$tmp"

  mkdir -p /etc/tgwebproxyr "${TWPR_ROOT}/docker"
  [[ -f "$src/settings.env" ]] && cp -a "$src/settings.env" /etc/tgwebproxyr/settings.env
  [[ -f "$src/bot.env" ]] && cp -a "$src/bot.env" /etc/tgwebproxyr/bot.env
  [[ -f "$src/profiles.json" ]] && install -m 0600 "$src/profiles.json" /etc/tgwebproxyr/profiles.json
  [[ -f "$src/autobackup.env" ]] && cp -a "$src/autobackup.env" /etc/tgwebproxyr/autobackup.env
  [[ -f "$src/docker.env" ]] && cp -a "$src/docker.env" "${TWPR_ROOT}/docker/.env"
  [[ -f "$src/.env" ]] && cp -a "$src/.env" "${TWPR_ROOT}/docker/.env"
  rm -rf "$tmp"

  TWPR_load_state
  TWPR_ensure_default_profile 2>/dev/null || true
  if TWPR_is_docker; then
    TWPR_docker_write_env 2>/dev/null || true
    TWPR_docker_compose up -d --force-recreate --remove-orphans 2>/dev/null || true
  else
    [[ -f /etc/tgwebproxyr/profiles.json ]] \
      && install -m 0400 /etc/tgwebproxyr/profiles.json /etc/tproxy-server/profiles.json 2>/dev/null || true
    systemctl restart mtproxy tproxy-server caddy tgwebproxyr-bot 2>/dev/null || true
  fi
  TWPR_ok "Восстановлено из $(basename "$archive")"
}

TWPR_autobackup_install_units() {
  cat >"$TWPR_AUTOBACKUP_UNIT" <<'EOF'
[Unit]
Description=TgWebProxyR autobackup
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/tgwebproxyr backup create --quiet
Nice=10
EOF
  chmod 0644 "$TWPR_AUTOBACKUP_UNIT"

  local calendar="daily"
  case "${TWPR_AUTOBACKUP}" in
    hourly) calendar="hourly" ;;
    daily) calendar="*-*-* 03:15:00" ;;
    monthly) calendar="*-*-01 03:15:00" ;;
    *) calendar="" ;;
  esac

  if [[ -z "$calendar" ]]; then
    systemctl disable --now tgwebproxyr-autobackup.timer 2>/dev/null || true
    rm -f "$TWPR_AUTOBACKUP_TIMER"
    systemctl daemon-reload 2>/dev/null || true
    return 0
  fi

  cat >"$TWPR_AUTOBACKUP_TIMER" <<EOF
[Unit]
Description=TgWebProxyR autobackup timer (${TWPR_AUTOBACKUP})

[Timer]
OnCalendar=${calendar}
Persistent=true
RandomizedDelaySec=120

[Install]
WantedBy=timers.target
EOF
  chmod 0644 "$TWPR_AUTOBACKUP_TIMER"
  systemctl daemon-reload
  systemctl enable --now tgwebproxyr-autobackup.timer
}

TWPR_cmd_autobackup() {
  TWPR_require_root
  TWPR_autobackup_load
  local sub="${1:-status}"
  case "$sub" in
    status|show)
      echo ""
      echo -e "  ${C_BOLD}Автобэкап${C_RESET}"
      echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
      TWPR_info "режим   ${TWPR_AUTOBACKUP:-off}"
      TWPR_info "в TG    ${TWPR_AUTOBACKUP_SEND:-1}"
      TWPR_info "хранить ${TWPR_AUTOBACKUP_KEEP:-12}"
      systemctl is-active --quiet tgwebproxyr-autobackup.timer 2>/dev/null \
        && TWPR_ok "timer active" \
        || TWPR_warn "timer off"
      systemctl list-timers tgwebproxyr-autobackup.timer --no-pager 2>/dev/null | head -n 3 || true
      ;;
    off|disable)
      TWPR_AUTOBACKUP=off
      TWPR_autobackup_save
      TWPR_autobackup_install_units
      TWPR_ok "автобэкап выключен"
      ;;
    hourly|daily|monthly)
      TWPR_AUTOBACKUP="$sub"
      TWPR_autobackup_save
      TWPR_autobackup_install_units
      TWPR_ok "автобэкап: ${sub}"
      ;;
    send|tg)
      local v="${2:-}"
      if [[ "$v" == "on" || "$v" == "1" ]]; then TWPR_AUTOBACKUP_SEND=1
      elif [[ "$v" == "off" || "$v" == "0" ]]; then TWPR_AUTOBACKUP_SEND=0
      else
        TWPR_AUTOBACKUP_SEND=$(( 1 - ${TWPR_AUTOBACKUP_SEND:-1} ))
      fi
      TWPR_autobackup_save
      TWPR_ok "отправка в TG: ${TWPR_AUTOBACKUP_SEND}"
      ;;
    *)
      echo "  tgwebproxyr backup auto status|off|hourly|daily|monthly"
      echo "  tgwebproxyr backup auto send on|off"
      ;;
  esac
}
