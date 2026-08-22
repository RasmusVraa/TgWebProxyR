#!/usr/bin/env bash
# TgWebProxyR — secret / profile helpers
# Реестр: /etc/tgwebproxyr/profiles.json (default всегда первый = TWPR_SECRET)
# Docker: монтируется в relay → entrypoint применяет все профили.

TWPR_ENGINE_PROFILES="${TWPR_ENGINE_PROFILES:-/etc/tproxy-server/profiles.json}"
TWPR_REGISTRY="${TWPR_REGISTRY:-${TWPR_STATE_DIR}/profiles.json}"

TWPR_ensure_default_profile() {
  [[ -n "${TWPR_SECRET:-}" ]] || return 0
  mkdir -p "$TWPR_STATE_DIR"
  local backend="127.0.0.1:${TWPR_PORT_MTPROXY:-2398}"
  local secret="$TWPR_SECRET"
  case "$secret" in
    dd????????????????????????????????) secret="${secret#dd}" ;;
  esac

  if command -v jq >/dev/null 2>&1; then
    local tmp
    tmp="$(mktemp)"
    if [[ -f "$TWPR_REGISTRY" ]]; then
      jq --arg s "$secret" --arg b "$backend" '
        .profiles = ((.profiles // []) | map(select(.name != "default")))
        | .profiles = [{name:"default", secret:$s, backend:$b, carrier_mode:"https"}] + .profiles
      ' "$TWPR_REGISTRY" >"$tmp" 2>/dev/null \
        || printf '{"profiles":[{"name":"default","secret":"%s","backend":"%s","carrier_mode":"https"}]}\n' \
             "$secret" "$backend" >"$tmp"
    else
      printf '{"profiles":[{"name":"default","secret":"%s","backend":"%s","carrier_mode":"https"}]}\n' \
        "$secret" "$backend" >"$tmp"
    fi
    install -m 0600 "$tmp" "$TWPR_REGISTRY"
    rm -f "$tmp"
  else
    umask 077
    cat >"$TWPR_REGISTRY" <<EOF
{"profiles":[{"name":"default","secret":"${secret}","backend":"${backend}","carrier_mode":"https"}]}
EOF
    chmod 600 "$TWPR_REGISTRY"
  fi
}

# Применить реестр к движку:
# - Docker: все секреты в mtproxy (-S…) + profiles в relay
# - Native: profiles.json + wrapper mtproxy со всеми -S
TWPR_profiles_apply_engine() {
  TWPR_ensure_default_profile
  local backend="127.0.0.1:${TWPR_PORT_MTPROXY:-2398}"

  if TWPR_is_docker 2>/dev/null; then
    [[ -f "$TWPR_REGISTRY" ]] || return 0
    TWPR_info "Применяю профили к Docker (mtproxy -S + relay)…"
    # shellcheck disable=SC1091
    source "${TWPR_ROOT}/lib/docker.sh" 2>/dev/null || true
    if declare -F TWPR_docker_compose >/dev/null 2>&1; then
      # mtproxy — якорь netns; после смены -S нужно пересоздать стек
      TWPR_docker_compose up -d --force-recreate --remove-orphans 2>/dev/null \
        || TWPR_docker_compose up -d --force-recreate 2>/dev/null || true
    fi
    return 0
  fi

  [[ -f "$TWPR_REGISTRY" ]] || return 0
  mkdir -p "$(dirname "$TWPR_ENGINE_PROFILES")"
  if command -v jq >/dev/null 2>&1; then
    local tmp
    tmp="$(mktemp)"
    jq --arg b "$backend" '
      .profiles |= map(.backend = $b | .carrier_mode = (.carrier_mode // "https"))
    ' "$TWPR_REGISTRY" >"$tmp"
    install -m 0400 "$tmp" "$TWPR_ENGINE_PROFILES"
    rm -f "$tmp"
  else
    install -m 0400 "$TWPR_REGISTRY" "$TWPR_ENGINE_PROFILES"
  fi

  TWPR_mtproxy_write_native_wrapper
  systemctl daemon-reload 2>/dev/null || true
  systemctl restart mtproxy 2>/dev/null || true
  systemctl restart tproxy-server 2>/dev/null || true
}

# Native: mtproto-proxy с несколькими -S из реестра (shared backend)
TWPR_mtproxy_write_native_wrapper() {
  local wrap="/opt/tgwebproxyr/bin/twpr-mtproxy.sh"
  local dropin_dir="/etc/systemd/system/mtproxy.service.d"
  mkdir -p /opt/tgwebproxyr/bin "$dropin_dir"

  cat >"$wrap" <<'EOF'
#!/bin/bash
set -euo pipefail
# shellcheck disable=SC1091
[[ -f /etc/mtproxy/mtproxy.env ]] && source /etc/mtproxy/mtproxy.env
REGISTRY="${TWPR_REGISTRY:-/etc/tgwebproxyr/profiles.json}"
BIN="/opt/MTProxy/objs/bin/mtproto-proxy"
WORKERS="${MTPROXY_WORKERS:-1}"
MAXC="${MTPROXY_MAX_CONNECTIONS:-4096}"

norm() {
  local s="${1:-}"
  case "$s" in
    dd????????????????????????????????) s="${s#dd}" ;;
  esac
  s="$(echo "$s" | tr 'A-F' 'a-f')"
  [[ "$s" =~ ^[0-9a-f]{32}$ ]] && echo "$s"
}

args=(-u mtproxy -p 8888 -H 2398)
declare -A seen=()
if [[ -f "$REGISTRY" ]] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r raw; do
    ns="$(norm "$raw" || true)"
    [[ -n "$ns" ]] || continue
    [[ -n "${seen[$ns]:-}" ]] && continue
    seen[$ns]=1
    args+=(-S "$ns")
  done < <(jq -r '.profiles[]?.secret // empty' "$REGISTRY")
fi
if [[ ${#seen[@]} -eq 0 ]] && [[ -n "${MTPROXY_SECRET:-}" ]]; then
  ns="$(norm "$MTPROXY_SECRET" || true)"
  [[ -n "$ns" ]] && args+=(-S "$ns")
fi
if [[ ${#args[@]} -le 4 ]]; then
  echo "twpr-mtproxy: нет секретов" >&2
  exit 1
fi

# --nat-info local:global (за NAT без этого MTProxy часто не ходит в Telegram)
nat="${MTPROXY_NAT_INFO:-${TWPR_MTPROXY_NAT_INFO:-}}"
case "$nat" in off|OFF|none|NONE|0|false|FALSE) nat="" ;; esac
ipv4() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && echo "$1"; }
if [[ -z "$nat" ]]; then
  lip="${MTPROXY_INTERNAL_IP:-}"
  lip="$(ipv4 "$lip" || true)"
  if [[ -z "$lip" ]] && command -v ip >/dev/null 2>&1; then
    lip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1);exit}}')"
    lip="$(ipv4 "$lip" || true)"
  fi
  gip="${MTPROXY_EXTERNAL_IP:-${TWPR_PUBLIC_IP:-}}"
  gip="$(ipv4 "$gip" || true)"
  if [[ -z "$gip" ]]; then
    for url in https://api.ipify.org https://ifconfig.me/ip https://icanhazip.com; do
      gip="$(curl -fsS --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
      gip="$(ipv4 "$gip" || true)"
      [[ -n "$gip" ]] && break
    done
  fi
  if [[ -n "$lip" && -n "$gip" && "$lip" != "$gip" ]]; then
    nat="${lip}:${gip}"
  fi
fi
if [[ -n "$nat" ]]; then
  echo "twpr-mtproxy: --nat-info ${nat}" >&2
  args+=(--nat-info "$nat")
fi

exec "$BIN" "${args[@]}" \
  --aes-pwd /etc/mtproxy/proxy-secret \
  /etc/mtproxy/proxy-multi.conf \
  -M "$WORKERS" -C "$MAXC"
EOF
  chmod 755 "$wrap"

  cat >"${dropin_dir}/twpr-multi-secret.conf" <<EOF
[Service]
# TgWebProxyR: несколько -S из /etc/tgwebproxyr/profiles.json
ExecStart=
ExecStart=${wrap}
EOF
  chmod 644 "${dropin_dir}/twpr-multi-secret.conf"
}

TWPR_registry_get_secret() {
  local name="${1:-default}"
  if [[ -f "$TWPR_REGISTRY" ]] && command -v jq >/dev/null 2>&1; then
    jq -r --arg n "$name" '.profiles[]? | select(.name==$n) | .secret' "$TWPR_REGISTRY" 2>/dev/null | head -1
  fi
}

TWPR_cmd_secret_show() {
  TWPR_load_state
  if TWPR_is_docker; then TWPR_docker_ensure_env 2>/dev/null || true; fi
  TWPR_ensure_default_profile
  local sec="${TWPR_SECRET:-}"
  [[ -z "$sec" ]] && sec="$(TWPR_registry_get_secret default)"
  [[ -z "$sec" ]] && { TWPR_err "Secret не сохранён"; return 1; }
  echo "$sec"
}

TWPR_cmd_secret_list() {
  TWPR_load_state
  if TWPR_is_docker; then TWPR_docker_ensure_env 2>/dev/null || true; fi
  TWPR_ensure_default_profile
  echo -e "  ${C_BOLD}Профили${C_RESET}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
  if [[ -f "$TWPR_REGISTRY" ]] && command -v jq >/dev/null 2>&1; then
    jq -r '.profiles[]? | "  \(.name)\t…\(.secret[-4:])\t\(.backend // "-")"' \
      "$TWPR_REGISTRY" 2>/dev/null || true
  elif [[ -n "${TWPR_SECRET:-}" ]]; then
    TWPR_ok "default  …${TWPR_SECRET: -4}"
  else
    TWPR_warn "пусто"
  fi
}

TWPR_cmd_secret_link() {
  local name="${1:-default}"
  TWPR_load_state
  if TWPR_is_docker; then TWPR_docker_ensure_env 2>/dev/null || true; fi
  TWPR_ensure_default_profile
  if [[ -z "$name" || "$name" == "default" ]]; then
    TWPR_cmd_link
    return
  fi
  local secret
  secret="$(TWPR_registry_get_secret "$name")"
  if [[ -z "$secret" || "$secret" == "null" ]]; then
    TWPR_err "Профиль не найден: ${name}"
    return 1
  fi
  echo ""
  echo -e "  ${C_BOLD}Профиль  ${name}${C_RESET}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
  echo "  Hostname  ${TWPR_HOSTNAME}"
  echo "  Secret    ${secret}"
  echo ""
  echo "  $(TWPR_tg_link "${TWPR_HOSTNAME}" "$secret")"
  echo "  $(TWPR_web_link "${TWPR_HOSTNAME}" "$secret")"
}

TWPR_secret_apply_docker() {
  local new_secret="$1"
  TWPR_SECRET="$new_secret"
  TWPR_save_state
  TWPR_ensure_default_profile
  TWPR_docker_write_env
  TWPR_info "Пересоздаю контейнеры с новым secret…"
  TWPR_docker_compose up -d --force-recreate --remove-orphans
}

TWPR_cmd_secret_rotate() {
  TWPR_require_root
  TWPR_load_state
  local new_secret choice="" name="${1:-default}"
  [[ -z "$name" ]] && name="default"
  new_secret="$(TWPR_gen_secret)"
  TWPR_info "Новый secret (${name}): ${C_BOLD}${new_secret}${C_RESET}"
  TWPR_ask_yn choice "Записать и перезапустить" "Y"
  [[ "$choice" == "yes" ]] || return 0

  if [[ "$name" == "default" ]]; then
    if TWPR_is_docker; then
      TWPR_secret_apply_docker "$new_secret"
      TWPR_ok "default обновлён (Docker)"
      TWPR_cmd_link
      return 0
    fi
    TWPR_SECRET="$new_secret"
    TWPR_save_state
    TWPR_ensure_default_profile
    if [[ -f /etc/mtproxy/mtproxy.env ]]; then
      sed -i "s/^MTPROXY_SECRET=.*/MTPROXY_SECRET=${new_secret}/" /etc/mtproxy/mtproxy.env || true
    fi
    TWPR_profiles_apply_engine
    TWPR_ok "default обновлён"
    TWPR_cmd_link
    return 0
  fi

  TWPR_ensure_default_profile
  command -v jq >/dev/null 2>&1 || { TWPR_err "Нужен jq"; return 1; }
  local tmp
  tmp="$(mktemp)"
  jq --arg n "$name" --arg s "$new_secret" '
    .profiles |= map(if .name == $n then .secret = $s else . end)
  ' "$TWPR_REGISTRY" >"$tmp"
  install -m 0600 "$tmp" "$TWPR_REGISTRY"
  rm -f "$tmp"
  TWPR_profiles_apply_engine
  TWPR_ok "Профиль ${name} обновлён"
  TWPR_cmd_secret_link "$name"
}

TWPR_cmd_secret_add() {
  TWPR_require_root
  TWPR_load_state
  TWPR_ensure_default_profile
  local name secret backend
  name="${1:-}"
  [[ -n "$name" ]] || TWPR_ask name "Имя пользователя" "user$(date +%s | tail -c 5)"
  name="$(echo "$name" | tr -cd 'A-Za-z0-9._-')"
  [[ -n "$name" ]] || { TWPR_err "пустое имя"; return 1; }
  [[ "$name" == "default" ]] && { TWPR_err "default уже есть — rotate"; return 1; }
  if [[ -f "$TWPR_REGISTRY" ]] && jq -e --arg n "$name" '.profiles[]|select(.name==$n)' "$TWPR_REGISTRY" >/dev/null 2>&1; then
    TWPR_err "Уже есть: ${name}"
    return 1
  fi
  secret="$(TWPR_gen_secret)"
  backend="127.0.0.1:${TWPR_PORT_MTPROXY:-2398}"
  TWPR_info "Secret для ${name}: ${secret}"

  command -v jq >/dev/null 2>&1 || { TWPR_err "Нужен jq"; return 1; }
  local tmp
  tmp="$(mktemp)"
  jq --arg n "$name" --arg s "$secret" --arg b "$backend" '
    .profiles += [{name:$n, secret:$s, backend:$b, carrier_mode:"https"}]
  ' "$TWPR_REGISTRY" >"$tmp"
  install -m 0600 "$tmp" "$TWPR_REGISTRY"
  rm -f "$tmp"

  TWPR_profiles_apply_engine
  TWPR_ok "Пользователь ${name} добавлен и применён к движку"
  TWPR_cmd_secret_link "$name"
}

TWPR_cmd_secret_rename() {
  TWPR_require_root
  TWPR_load_state
  local old="${1:-}" new="${2:-}"
  [[ -n "$old" ]] || TWPR_ask old "Старое имя"
  [[ -n "$new" ]] || TWPR_ask new "Новое имя"
  new="$(echo "$new" | tr -cd 'A-Za-z0-9._-')"
  [[ "$old" == "default" ]] && { TWPR_err "default нельзя переименовать"; return 1; }
  [[ -z "$new" || "$new" == "default" ]] && { TWPR_err "некорректное имя"; return 1; }
  command -v jq >/dev/null 2>&1 || { TWPR_err "Нужен jq"; return 1; }
  TWPR_ensure_default_profile
  local tmp
  tmp="$(mktemp)"
  jq --arg o "$old" --arg n "$new" '
    if ([.profiles[]|select(.name==$o)]|length)==0 then error("not found") else . end
    | .profiles |= map(if .name == $o then .name = $n else . end)
  ' "$TWPR_REGISTRY" >"$tmp" 2>/dev/null || { rm -f "$tmp"; TWPR_err "нет профиля ${old}"; return 1; }
  install -m 0600 "$tmp" "$TWPR_REGISTRY"
  rm -f "$tmp"
  TWPR_profiles_apply_engine
  TWPR_ok "${old} → ${new}"
}

TWPR_cmd_secret_remove() {
  TWPR_require_root
  TWPR_load_state
  local name="${1:-}" choice=""
  [[ -n "$name" ]] || TWPR_ask name "Имя профиля для удаления"
  [[ "$name" == "default" ]] && {
    TWPR_err "default нельзя удалить — только rotate"
    return 1
  }
  TWPR_ensure_default_profile
  if [[ "${TWPR_YES:-}" != "1" ]]; then
    TWPR_ask_yn choice "Удалить профиль ${name}" "n"
    [[ "$choice" == "yes" ]] || return 0
  fi
  command -v jq >/dev/null 2>&1 || { TWPR_err "Нужен jq"; return 1; }
  local tmp
  tmp="$(mktemp)"
  jq --arg n "$name" '.profiles |= map(select(.name != $n))' "$TWPR_REGISTRY" >"$tmp"
  install -m 0600 "$tmp" "$TWPR_REGISTRY"
  rm -f "$tmp"
  TWPR_profiles_apply_engine
  TWPR_ok "Удалён: ${name}"
}

TWPR_cmd_secret_apply() {
  TWPR_require_root
  TWPR_load_state
  if TWPR_is_docker; then TWPR_docker_ensure_env 2>/dev/null || true; fi
  TWPR_profiles_apply_engine
  TWPR_ok "Профили применены к движку"
}
