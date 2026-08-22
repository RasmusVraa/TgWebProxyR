#!/usr/bin/env bash
# TgWebProxyR — config backups

TWPR_BACKUP_DIR="${TWPR_BACKUP_DIR:-/opt/tgwebproxyr/backups}"

TWPR_cmd_backup() {
  local sub="${1:-create}"
  shift || true
  case "$sub" in
    create|new) TWPR_backup_create ;;
    list) TWPR_backup_list ;;
    restore) TWPR_backup_restore "${1:-}" ;;
    *) echo "  tgwebproxyr backup create|list|restore <name>" ;;
  esac
}

TWPR_backup_create() {
  TWPR_require_root
  mkdir -p "$TWPR_BACKUP_DIR"
  local stamp dest
  stamp="$(date -u +%Y%m%d-%H%M%S)"
  dest="${TWPR_BACKUP_DIR}/twpr-${stamp}"
  mkdir -p "$dest"
  for f in \
    /etc/tgwebproxyr/settings.env \
    /etc/tgwebproxyr/bot.env \
    /etc/tproxy-server/profiles.json \
    /etc/tproxy-server/config.json \
    /etc/caddy/Caddyfile \
    /etc/mtproxy/mtproxy.env \
    "${TWPR_ROOT}/docker/.env"; do
    [[ -f "$f" ]] && cp -a "$f" "$dest/"
  done
  cat >"$dest/meta.json" <<EOF
{"created_at":"${stamp}","hostname":"${TWPR_HOSTNAME:-}","version":"${TWPR_VERSION:-}","mode":"${TWPR_DEPLOY_MODE:-}"}
EOF
  TWPR_ok "Бэкап: ${dest}"
}

TWPR_backup_list() {
  mkdir -p "$TWPR_BACKUP_DIR"
  echo ""
  echo -e "  ${C_BOLD}Бэкапы${C_RESET} → ${TWPR_BACKUP_DIR}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
  local d
  local found=0
  for d in "$TWPR_BACKUP_DIR"/twpr-*; do
    [[ -d "$d" ]] || continue
    found=1
    TWPR_info "$(basename "$d")"
  done
  [[ "$found" -eq 1 ]] || TWPR_warn "пока пусто"
}

TWPR_backup_restore() {
  TWPR_require_root
  local name="$1"
  [[ -n "$name" ]] || { TWPR_err "укажите имя каталога бэкапа"; return 1; }
  local src="${TWPR_BACKUP_DIR}/${name}"
  [[ -d "$src" ]] || src="$name"
  [[ -d "$src" ]] || { TWPR_err "нет бэкапа: ${name}"; return 1; }

  TWPR_warn "Восстановление из ${src}"
  local choice=""
  TWPR_ask_yn choice "Продолжить" "n"
  [[ "$choice" == "yes" ]] || return 0

  [[ -f "$src/settings.env" ]] && cp -a "$src/settings.env" /etc/tgwebproxyr/settings.env
  [[ -f "$src/bot.env" ]] && cp -a "$src/bot.env" /etc/tgwebproxyr/bot.env
  [[ -f "$src/profiles.json" ]] && install -m 0400 "$src/profiles.json" /etc/tproxy-server/profiles.json
  [[ -f "$src/config.json" ]] && cp -a "$src/config.json" /etc/tproxy-server/config.json
  [[ -f "$src/Caddyfile" ]] && cp -a "$src/Caddyfile" /etc/caddy/Caddyfile
  [[ -f "$src/mtproxy.env" ]] && cp -a "$src/mtproxy.env" /etc/mtproxy/mtproxy.env
  if [[ -f "$src/.env" ]]; then
    mkdir -p "${TWPR_ROOT}/docker"
    cp -a "$src/.env" "${TWPR_ROOT}/docker/.env"
  fi

  TWPR_load_state
  if TWPR_is_docker; then
    TWPR_docker_compose up -d --force-recreate --remove-orphans 2>/dev/null || true
  else
    systemctl restart mtproxy tproxy-server caddy tgwebproxyr-bot 2>/dev/null || true
  fi
  TWPR_ok "Восстановлено"
  TWPR_cmd_status
}
