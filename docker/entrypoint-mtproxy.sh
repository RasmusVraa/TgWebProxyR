#!/bin/sh
set -eu

SECRET="${MTPROXY_SECRET:?MTPROXY_SECRET required}"
WORKERS="${MTPROXY_WORKERS:-1}"
MAXC="${MTPROXY_MAX_CONNECTIONS:-4096}"
CFG=/etc/mtproxy

# strip dd prefix if present — mtproto-proxy -S wants 32 hex
case "$SECRET" in
  dd????????????????????????????????) SECRET="${SECRET#dd}" ;;
esac

mkdir -p "$CFG"

if [ ! -s "${CFG}/proxy-secret" ] || [ ! -s "${CFG}/proxy-multi.conf" ]; then
  echo ">> fetching Telegram proxy secret/config…"
  curl -fsSL -o "${CFG}/proxy-secret" https://core.telegram.org/getProxySecret
  curl -fsSL -o "${CFG}/proxy-multi.conf" https://core.telegram.org/getProxyConfig
fi

# -H client port, -p stats port; bind all interfaces inside the container network
exec /opt/MTProxy/objs/bin/mtproto-proxy \
  -u mtproxy \
  -p 8888 \
  -H 2398 \
  -S "$SECRET" \
  --aes-pwd "${CFG}/proxy-secret" \
  "${CFG}/proxy-multi.conf" \
  -M "$WORKERS" \
  -C "$MAXC"
