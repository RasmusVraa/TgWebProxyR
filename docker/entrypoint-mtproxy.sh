#!/bin/sh
set -eu

SECRET="${MTPROXY_SECRET:?MTPROXY_SECRET required}"
WORKERS="${MTPROXY_WORKERS:-1}"
MAXC="${MTPROXY_MAX_CONNECTIONS:-4096}"
CFG=/etc/mtproxy
DEFAULTS=/usr/share/mtproxy-defaults

case "$SECRET" in
  dd????????????????????????????????) SECRET="${SECRET#dd}" ;;
esac

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

exec /opt/MTProxy/objs/bin/mtproto-proxy \
  -u mtproxy \
  -p 8888 \
  -H 2398 \
  -S "$SECRET" \
  --aes-pwd "${CFG}/proxy-secret" \
  "${CFG}/proxy-multi.conf" \
  -M "$WORKERS" \
  -C "$MAXC"
