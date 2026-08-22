#!/bin/sh
set -eu

SECRET="${MTPROXY_SECRET:-}"
WORKERS="${MTPROXY_WORKERS:-1}"
MAXC="${MTPROXY_MAX_CONNECTIONS:-4096}"
CFG=/etc/mtproxy
DEFAULTS=/usr/share/mtproxy-defaults
HOST_PROFILES="${TWPR_HOST_PROFILES:-/run/twpr/profiles.json}"

# jq нужен для списка секретов из profiles.json (старые образы)
if ! command -v jq >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq >/dev/null 2>&1 || true
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq jq >/dev/null 2>&1 || true
  fi
fi

normalize_secret() {
  s="$1"
  case "$s" in
    dd????????????????????????????????) s="${s#dd}" ;;
  esac
  # только 32 hex
  echo "$s" | tr 'A-F' 'a-f' | grep -E '^[0-9a-f]{32}$' || true
}

mkdir -p "$CFG"

# том может перекрыть /etc/mtproxy — копируем запечённые файлы из образа
if [ ! -s "${CFG}/proxy-secret" ] || [ ! -s "${CFG}/proxy-multi.conf" ]; then
  if [ -s "${DEFAULTS}/proxy-secret" ] && [ -s "${DEFAULTS}/proxy-multi.conf" ]; then
    echo ">> using baked Telegram proxy config"
    cp -f "${DEFAULTS}/proxy-secret" "${CFG}/proxy-secret"
    cp -f "${DEFAULTS}/proxy-multi.conf" "${CFG}/proxy-multi.conf"
  else
    echo ">> fetching Telegram proxy secret/config…"
    curl -fsSL --retry 5 --retry-delay 2 -o "${CFG}/proxy-secret" https://core.telegram.org/getProxySecret
    curl -fsSL --retry 5 --retry-delay 2 -o "${CFG}/proxy-multi.conf" https://core.telegram.org/getProxyConfig
  fi
fi

# Собрать уникальные -S: все профили + fallback MTPROXY_SECRET
# Official MTProxy: несколько -S на одном процессе — когда профили делят backend/политику
SECRETS_FILE="$(mktemp)"
trap 'rm -f "$SECRETS_FILE"' EXIT

if [ -s "$HOST_PROFILES" ] && command -v jq >/dev/null 2>&1; then
  echo ">> mtproxy secrets from host profiles"
  jq -r '.profiles[]?.secret // empty' "$HOST_PROFILES" 2>/dev/null | while read -r raw; do
    ns="$(normalize_secret "$raw")"
    [ -n "$ns" ] && echo "$ns"
  done | sort -u >"$SECRETS_FILE"
fi

if [ ! -s "$SECRETS_FILE" ] && [ -n "$SECRET" ]; then
  ns="$(normalize_secret "$SECRET")"
  [ -n "$ns" ] && echo "$ns" >"$SECRETS_FILE"
fi

if [ ! -s "$SECRETS_FILE" ]; then
  echo "ERROR: no MTProxy secrets (MTPROXY_SECRET / profiles.json)" >&2
  exit 1
fi

echo ">> mtproxy -S count: $(wc -l <"$SECRETS_FILE" | tr -d ' ')"

# --nat-info local:global — без этого за Docker/NAT часто «Updating…» / нет связи с DC
# Override: MTPROXY_NAT_INFO=local:global | off
detect_ipv4() {
  echo "$1" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true
}

detect_local_ip() {
  lip=""
  if command -v ip >/dev/null 2>&1; then
    lip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}')"
  fi
  lip="$(detect_ipv4 "$lip")"
  if [ -z "$lip" ]; then
    lip="$(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | grep -v '^127\.' | head -n 1 || true)"
  fi
  echo "$lip"
}

detect_public_ip() {
  # явный override
  gip="$(detect_ipv4 "${MTPROXY_EXTERNAL_IP:-${TWPR_PUBLIC_IP:-}}")"
  if [ -n "$gip" ]; then
    echo "$gip"
    return 0
  fi
  for url in \
    "https://api.ipify.org" \
    "https://ifconfig.me/ip" \
    "https://icanhazip.com"; do
    gip="$(curl -fsS --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]' || true)"
    gip="$(detect_ipv4 "$gip")"
    if [ -n "$gip" ]; then
      echo "$gip"
      return 0
    fi
  done
  return 1
}

NAT_INFO="${MTPROXY_NAT_INFO:-${TWPR_MTPROXY_NAT_INFO:-}}"
case "$NAT_INFO" in
  off|OFF|none|NONE|0|false|FALSE) NAT_INFO="" ;;
  "")
    LOCAL_IP="$(detect_local_ip)"
    # INTERNAL_IP override
    [ -n "${MTPROXY_INTERNAL_IP:-}" ] && LOCAL_IP="$(detect_ipv4 "$MTPROXY_INTERNAL_IP")"
    GLOBAL_IP="$(detect_public_ip || true)"
    if [ -n "$LOCAL_IP" ] && [ -n "$GLOBAL_IP" ] && [ "$LOCAL_IP" != "$GLOBAL_IP" ]; then
      NAT_INFO="${LOCAL_IP}:${GLOBAL_IP}"
    elif [ -n "$LOCAL_IP" ] && [ -n "$GLOBAL_IP" ]; then
      echo ">> nat-info skip (local==public ${LOCAL_IP})"
    else
      echo ">> WARN: cannot auto-detect nat-info (local=${LOCAL_IP:-?} public=${GLOBAL_IP:-?})"
      echo ">> set MTPROXY_NAT_INFO=LOCAL:PUBLIC or MTPROXY_EXTERNAL_IP=…"
    fi
    ;;
esac

# POSIX: собрать argv
set -- /opt/MTProxy/objs/bin/mtproto-proxy \
  -u mtproxy \
  -p 8888 \
  -H 2398

while read -r ns; do
  [ -n "$ns" ] || continue
  set -- "$@" -S "$ns"
done <"$SECRETS_FILE"

if [ -n "$NAT_INFO" ]; then
  echo ">> mtproxy --nat-info ${NAT_INFO}"
  set -- "$@" --nat-info "$NAT_INFO"
fi

set -- "$@" \
  --aes-pwd "${CFG}/proxy-secret" \
  "${CFG}/proxy-multi.conf" \
  -M "$WORKERS" \
  -C "$MAXC"

exec "$@"
