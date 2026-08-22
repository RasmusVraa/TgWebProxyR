#!/usr/bin/env bash
# TgWebProxyR — TLS / ACME: подхват существующего сертификата

# TWPR_TLS_MODE=acme|file
# TWPR_TLS_CERT / TWPR_TLS_KEY — пути к fullchain и privkey

TWPR_certs_normalize_host() {
  echo "${1:-}" | tr '[:upper:]' '[:lower:]' | sed 's/\.$//'
}

# Найти пару fullchain+privkey для hostname. Печатает: CERT|KEY|SOURCE
TWPR_certs_find() {
  local host
  host="$(TWPR_certs_normalize_host "${1:-${TWPR_HOSTNAME:-}}")"
  [[ -n "$host" ]] || return 1

  local cert="" key="" src=""

  if [[ -n "${TWPR_TLS_CERT:-}" && -n "${TWPR_TLS_KEY:-}" ]] \
     && [[ -f "$TWPR_TLS_CERT" && -f "$TWPR_TLS_KEY" ]]; then
    cert="$TWPR_TLS_CERT"
    key="$TWPR_TLS_KEY"
    src="env"
  elif [[ -f "/etc/letsencrypt/live/${host}/fullchain.pem" \
       && -f "/etc/letsencrypt/live/${host}/privkey.pem" ]]; then
    cert="/etc/letsencrypt/live/${host}/fullchain.pem"
    key="/etc/letsencrypt/live/${host}/privkey.pem"
    src="letsencrypt"
  elif [[ -f "/etc/ssl/tgwebproxyr/${host}/fullchain.pem" \
       && -f "/etc/ssl/tgwebproxyr/${host}/privkey.pem" ]]; then
    cert="/etc/ssl/tgwebproxyr/${host}/fullchain.pem"
    key="/etc/ssl/tgwebproxyr/${host}/privkey.pem"
    src="ssl-twpr"
  elif [[ -f "/etc/tgwebproxyr/certs/fullchain.pem" \
       && -f "/etc/tgwebproxyr/certs/privkey.pem" ]]; then
    cert="/etc/tgwebproxyr/certs/fullchain.pem"
    key="/etc/tgwebproxyr/certs/privkey.pem"
    src="state-certs"
  else
    return 1
  fi

  [[ -s "$cert" && -s "$key" ]] || return 1
  printf '%s|%s|%s\n' "$cert" "$key" "$src"
}

TWPR_certs_probe_and_choose() {
  local host found cert key src choice=""
  host="$(TWPR_certs_normalize_host "${TWPR_HOSTNAME:-}")"
  [[ -n "$host" ]] || { TWPR_TLS_MODE="${TWPR_TLS_MODE:-acme}"; return 0; }

  if [[ "${TWPR_TLS_MODE:-}" == "file" ]] \
     && [[ -n "${TWPR_TLS_CERT:-}" && -n "${TWPR_TLS_KEY:-}" ]] \
     && [[ -f "$TWPR_TLS_CERT" && -f "$TWPR_TLS_KEY" ]]; then
    TWPR_ok "TLS: файлы ${TWPR_TLS_CERT}"
    return 0
  fi

  found="$(TWPR_certs_find "$host" || true)"
  if [[ -z "$found" ]]; then
    TWPR_TLS_MODE="acme"
    TWPR_TLS_CERT=""
    TWPR_TLS_KEY=""
    TWPR_info "TLS: сертификат на диске не найден — Let's Encrypt (ACME)"
    return 0
  fi

  IFS='|' read -r cert key src <<<"$found"
  TWPR_ok "Найден сертификат (${src}):"
  echo "    cert  ${cert}"
  echo "    key   ${key}"

  if [[ "${TWPR_YES:-}" == "1" ]]; then
    choice="yes"
  else
    TWPR_ask_yn choice "Подхватить его (не выпускать новый ACME)" "Y"
  fi

  if [[ "$choice" == "yes" ]]; then
    TWPR_TLS_MODE="file"
    TWPR_TLS_CERT="$cert"
    TWPR_TLS_KEY="$key"
    TWPR_ok "TLS: режим file — новый сертификат не выпускается"
  else
    TWPR_TLS_MODE="acme"
    TWPR_TLS_CERT=""
    TWPR_TLS_KEY=""
    TWPR_info "TLS: режим ACME (Let's Encrypt)"
  fi
}

# Пути cert/key внутри контейнера caddy → две строки
TWPR_certs_container_paths() {
  case "${TWPR_TLS_CERT:-}" in
    /etc/letsencrypt/*)
      local h
      h="$(TWPR_certs_normalize_host "$TWPR_HOSTNAME")"
      echo "/etc/letsencrypt/live/${h}/fullchain.pem"
      echo "/etc/letsencrypt/live/${h}/privkey.pem"
      ;;
    *)
      echo "/run/twpr/tls/fullchain.pem"
      echo "/run/twpr/tls/privkey.pem"
      ;;
  esac
}

# dest: путь к Caddyfile; для docker/Caddyfile пишем container-paths
TWPR_write_caddyfile() {
  local dest="${1:?}"
  local host email http https relay
  host="$(TWPR_certs_normalize_host "${TWPR_HOSTNAME:?hostname required}")"
  email="${TWPR_EMAIL:-admin@${host}}"
  http="${TWPR_PORT_HTTP:-80}"
  https="${TWPR_PORT_HTTPS:-443}"
  relay="${TWPR_PORT_RELAY:-8080}"

  local tls_line="" global_extra
  if [[ "${TWPR_TLS_MODE:-acme}" == "file" && -n "${TWPR_TLS_CERT:-}" && -n "${TWPR_TLS_KEY:-}" ]]; then
    local cpath kpath
    if [[ "$dest" == *"/docker/Caddyfile" || "$dest" == */docker/Caddyfile ]]; then
      cpath="$(TWPR_certs_container_paths | sed -n '1p')"
      kpath="$(TWPR_certs_container_paths | sed -n '2p')"
    else
      cpath="$TWPR_TLS_CERT"
      kpath="$TWPR_TLS_KEY"
    fi
    tls_line="	tls ${cpath} ${kpath}"
    global_extra="# existing certificate — ACME disabled"
  else
    global_extra="email ${email}"
  fi

  mkdir -p "$(dirname "$dest")"
  {
    echo "{"
    echo "	${global_extra}"
    echo "	admin off"
    echo "	http_port ${http}"
    echo "	https_port ${https}"
    echo "	servers {"
    echo "		protocols h1 h2"
    echo "		timeouts {"
    echo "			read_header 10s"
    echo "			read_body 60s"
    echo "		}"
    echo "	}"
    echo "}"
    echo ""
    echo "${host} {"
    if [[ -n "$tls_line" ]]; then
      echo "$tls_line"
    fi
    cat <<'SITE'
	encode zstd gzip
	header Strict-Transport-Security "max-age=31536000; includeSubDomains"
	reverse_proxy 127.0.0.1:RELAY_PORT {
		transport http {
			response_header_timeout 40s
		}
	}

	handle_errors {
		header {
			Cache-Control "no-store"
			Content-Security-Policy "default-src 'self'; style-src 'self'; img-src 'self'; worker-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
			Permissions-Policy "camera=(), microphone=(), geolocation=()"
			Referrer-Policy "strict-origin-when-cross-origin"
			X-Content-Type-Options "nosniff"
			X-Frame-Options "DENY"
			Strict-Transport-Security "max-age=31536000; includeSubDomains"
		}
		respond "{http.error.status_code} {http.error.status_text}" {http.error.status_code}
	}
}
SITE
  } | sed "s/RELAY_PORT/${relay}/g" >"$dest"

  chmod 644 "$dest"
  TWPR_ok "Caddyfile → ${dest} (TLS=${TWPR_TLS_MODE:-acme})"
}

TWPR_certs_prepare_docker() {
  local dir="${TWPR_DOCKER_DIR:-${TWPR_ROOT}/docker}"
  TWPR_write_caddyfile "${dir}/Caddyfile"

  local override="${dir}/docker-compose.tls.yml"
  if [[ "${TWPR_TLS_MODE:-}" == "file" && -n "${TWPR_TLS_CERT:-}" && -n "${TWPR_TLS_KEY:-}" ]]; then
    case "${TWPR_TLS_CERT}" in
      /etc/letsencrypt/*)
        cat >"$override" <<EOF
# auto-generated by TgWebProxyR — reuse Let's Encrypt
services:
  caddy:
    volumes:
      - /etc/letsencrypt:/etc/letsencrypt:ro
EOF
        ;;
      *)
        cat >"$override" <<EOF
# auto-generated by TgWebProxyR — reuse TLS files
services:
  caddy:
    volumes:
      - ${TWPR_TLS_CERT}:/run/twpr/tls/fullchain.pem:ro
      - ${TWPR_TLS_KEY}:/run/twpr/tls/privkey.pem:ro
EOF
        ;;
    esac
    chmod 644 "$override"
    TWPR_ok "Docker TLS override: $(basename "$override")"
  else
    rm -f "$override"
  fi
}

TWPR_certs_apply_native() {
  TWPR_write_caddyfile /etc/caddy/Caddyfile
  systemctl reload caddy 2>/dev/null || systemctl restart caddy 2>/dev/null || true
}

TWPR_cmd_certs() {
  local sub="${1:-status}"
  TWPR_load_state
  case "$sub" in
    status|show)
      echo ""
      echo -e "  ${C_BOLD}TLS${C_RESET}"
      echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
      TWPR_info "hostname  ${TWPR_HOSTNAME:-—}"
      TWPR_info "mode      ${TWPR_TLS_MODE:-acme}"
      if [[ "${TWPR_TLS_MODE:-}" == "file" ]]; then
        TWPR_info "cert      ${TWPR_TLS_CERT:-—}"
        TWPR_info "key       ${TWPR_TLS_KEY:-—}"
      else
        TWPR_info "email     ${TWPR_EMAIL:-—}"
      fi
      local found
      found="$(TWPR_certs_find "${TWPR_HOSTNAME:-}" || true)"
      if [[ -n "$found" ]]; then
        TWPR_ok "на диске есть: ${found}"
      else
        TWPR_info "внешний cert для hostname не найден"
      fi
      ;;
    detect|scan)
      TWPR_certs_probe_and_choose
      TWPR_save_state
      if TWPR_is_docker; then
        TWPR_certs_prepare_docker
        TWPR_docker_compose up -d --force-recreate --no-deps caddy 2>/dev/null || true
      else
        TWPR_certs_apply_native
      fi
      ;;
    *)
      echo "  tgwebproxyr certs status|detect"
      ;;
  esac
}
