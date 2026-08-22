#!/usr/bin/env bash
# TgWebProxyR — port selection and post-install patching

TWPR_port_ok() {
  local p="$1"
  [[ "$p" =~ ^[1-9][0-9]{0,4}$ ]] && ((p >= 1 && p <= 65535))
}

TWPR_port_busy() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lnt "( sport = :$p )" 2>/dev/null | grep -q ":$p"
    return $?
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -lnt 2>/dev/null | grep -qE "[.:]$p[[:space:]]"
    return $?
  fi
  return 1
}

TWPR_ask_port() {
  # TWPR_ask_port VAR "label" default [public|local]
  local __var="$1" __label="$2" __default="$3" __kind="${4:-public}" __p="" __choice=""
  while true; do
    TWPR_ask __p "$__label" "$__default"
    if ! TWPR_port_ok "$__p"; then
      TWPR_warn "Порт должен быть числом 1–65535"
      continue
    fi
    if TWPR_port_busy "$__p"; then
      TWPR_warn "Порт ${__p} уже занят на этом сервере"
      TWPR_ask_yn __choice "Всё равно использовать ${__p}" "n"
      [[ "$__choice" == "yes" ]] || continue
    fi
    if [[ "$__kind" == "public" && "$__p" != "443" && "$__label" == *HTTPS* ]]; then
      TWPR_warn "Telegram WEB-клиент всегда ходит на 443."
      TWPR_warn "Не-443 имеет смысл только с DNAT/прокси спереди."
      TWPR_ask_yn __choice "Оставить HTTPS=${__p}" "n"
      [[ "$__choice" == "yes" ]] || continue
    fi
    printf -v "$__var" '%s' "$__p"
    return 0
  done
}

TWPR_wizard_ask_ports() {
  TWPR_step 5 "$TWPR_TOTAL_STEPS" "Рабочие порты"
  echo "  Публичные — снаружи; локальные — только 127.0.0.1"
  echo "  Клиент Telegram WEB всегда ожидает HTTPS :443."
  echo ""

  local http https relay admin mtproxy choice=""
  TWPR_ask_yn choice "Оставить стандартные 80/443 + 8080/8081/2398" "Y"
  if [[ "$choice" == "yes" ]]; then
    TWPR_PORT_HTTP=80
    TWPR_PORT_HTTPS=443
    TWPR_PORT_RELAY=8080
    TWPR_PORT_ADMIN=8081
    TWPR_PORT_MTPROXY=2398
    TWPR_ok "Порты: HTTP=80 HTTPS=443 relay=8080 admin=8081 mtproxy=2398"
    return 0
  fi

  TWPR_ask_port http "HTTP (ACME / redirect)" "${TWPR_PORT_HTTP:-80}" public
  TWPR_ask_port https "HTTPS (публичный)" "${TWPR_PORT_HTTPS:-443}" public
  TWPR_ask_port relay "Relay (локальный)" "${TWPR_PORT_RELAY:-8080}" local
  TWPR_ask_port admin "Admin/metrics (локальный)" "${TWPR_PORT_ADMIN:-8081}" local
  TWPR_ask_port mtproxy "MTProxy backend (локальный)" "${TWPR_PORT_MTPROXY:-2398}" local

  # uniqueness check for local trio + public pair overlaps on same host are ok across interfaces
  if [[ "$relay" == "$admin" || "$relay" == "$mtproxy" || "$admin" == "$mtproxy" ]]; then
    TWPR_err "Локальные порты relay/admin/mtproxy должны отличаться"
    exit 1
  fi
  if [[ "$http" == "$https" ]]; then
    TWPR_err "HTTP и HTTPS порты должны отличаться"
    exit 1
  fi

  TWPR_PORT_HTTP="$http"
  TWPR_PORT_HTTPS="$https"
  TWPR_PORT_RELAY="$relay"
  TWPR_PORT_ADMIN="$admin"
  TWPR_PORT_MTPROXY="$mtproxy"
  TWPR_ok "HTTP=${http} HTTPS=${https} relay=${relay} admin=${admin} mtproxy=${mtproxy}"
}

TWPR_apply_ports() {
  local http="${TWPR_PORT_HTTP:-80}"
  local https="${TWPR_PORT_HTTPS:-443}"
  local relay="${TWPR_PORT_RELAY:-8080}"
  local admin="${TWPR_PORT_ADMIN:-8081}"
  local mtproxy="${TWPR_PORT_MTPROXY:-2398}"

  TWPR_info "Применяю порты: HTTP=${http} HTTPS=${https} relay=${relay} admin=${admin} mtproxy=${mtproxy}"

  # --- Caddyfile ---
  if [[ -f /etc/caddy/Caddyfile ]]; then
    local tmp
    tmp="$(mktemp)"
    # Strip old http_port/https_port lines, then inject fresh ones after opening global brace
    awk -v http="$http" -v https="$https" -v relay="$relay" '
      BEGIN { injected=0 }
      /^[[:space:]]*http_port[[:space:]]+/ { next }
      /^[[:space:]]*https_port[[:space:]]+/ { next }
      {
        if ($0 ~ /reverse_proxy[[:space:]]+127\.0\.0\.1:[0-9]+/) {
          sub(/127\.0\.0\.1:[0-9]+/, "127.0.0.1:" relay)
        }
        print
        if (injected==0 && $0 ~ /^\{[[:space:]]*$/) {
          print "\thttp_port " http
          print "\thttps_port " https
          injected=1
        }
      }
    ' /etc/caddy/Caddyfile >"$tmp"
    # If there was no top-level { block, prepend a global block
    if ! grep -qE '^[[:space:]]*http_port[[:space:]]+' "$tmp"; then
      {
        echo "{"
        echo "	http_port ${http}"
        echo "	https_port ${https}"
        echo "}"
        cat "$tmp"
      } >"${tmp}.2"
      mv "${tmp}.2" "$tmp"
    fi
    install -m 0644 "$tmp" /etc/caddy/Caddyfile
    rm -f "$tmp"
    TWPR_ok "Caddyfile → http_port=${http} https_port=${https} upstream=${relay}"
  fi

  # --- tproxy-server config.json ---
  if [[ -f /etc/tproxy-server/config.json ]] && command -v jq >/dev/null 2>&1; then
    local tmp
    tmp="$(mktemp)"
    jq --arg l "127.0.0.1:${relay}" --arg a "127.0.0.1:${admin}" \
      '.listen=$l | .admin_listen=$a' \
      /etc/tproxy-server/config.json >"$tmp"
    install -m 0644 "$tmp" /etc/tproxy-server/config.json
    rm -f "$tmp"
    TWPR_ok "config.json listen=${relay} admin=${admin}"
  fi

  # --- profiles backend ---
  if [[ -f /etc/tproxy-server/profiles.json ]] && command -v jq >/dev/null 2>&1; then
    local tmp
    tmp="$(mktemp)"
    jq --arg b "127.0.0.1:${mtproxy}" '.profiles |= map(.backend=$b)' \
      /etc/tproxy-server/profiles.json >"$tmp"
    install -m 0400 "$tmp" /etc/tproxy-server/profiles.json
    rm -f "$tmp"
    TWPR_ok "profiles backend → 127.0.0.1:${mtproxy}"
  fi

  # --- mtproxy.service -H ---
  if [[ -f /etc/systemd/system/mtproxy.service ]]; then
    sed -i -E "s/-H[[:space:]]+[0-9]+/-H ${mtproxy}/g" /etc/systemd/system/mtproxy.service
    TWPR_ok "mtproxy.service -H ${mtproxy}"
  fi

  # --- nftables ---
  nft delete table inet tproxy_backend 2>/dev/null || true
  nft -f - <<EOF 2>/dev/null || true
table inet tproxy_backend {
	chain local_backend {
		type filter hook input priority -10; policy accept;
		iifname != "lo" tcp dport { ${mtproxy}, 8888 } drop
	}
}
EOF
  TWPR_ok "nftables: drop внешний доступ к ${mtproxy}/8888"

  systemctl daemon-reload 2>/dev/null || true
  # пересобрать Caddyfile с учётом TLS mode (не затирать file→acme)
  if declare -F TWPR_write_caddyfile >/dev/null 2>&1; then
    if [[ -n "${TWPR_HOSTNAME:-}" ]]; then
      TWPR_write_caddyfile /etc/caddy/Caddyfile
    fi
  fi
  systemctl restart mtproxy tproxy-server caddy 2>/dev/null || true
}

TWPR_open_firewall() {
  local http="${TWPR_PORT_HTTP:-80}"
  local https="${TWPR_PORT_HTTPS:-443}"
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi 'Status: active'; then
    TWPR_info "UFW активен — открываю ${http}/tcp и ${https}/tcp"
    ufw allow "${http}/tcp" >/dev/null 2>&1 || true
    ufw allow "${https}/tcp" >/dev/null 2>&1 || true
  fi
}
