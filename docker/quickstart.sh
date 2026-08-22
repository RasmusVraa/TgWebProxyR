#!/usr/bin/env bash
# TgWebProxyR Docker — быстрый подъём стека
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_DIR="${ROOT}/docker"
ENV_FILE="${DOCKER_DIR}/.env"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Нужен $1" >&2; exit 1; }; }
need docker
docker compose version >/dev/null 2>&1 || { echo "Нужен Docker Compose v2 (docker compose)" >&2; exit 1; }

ask() {
  local __v="$1" __p="$2" __d="${3-}" __r=""
  if [[ -n "$__d" ]]; then
    read -r -p "  ${__p} [${__d}]: " __r || true
    __r="${__r:-$__d}"
  else
    read -r -p "  ${__p}: " __r
  fi
  printf -v "$__v" '%s' "$__r"
}

gen_secret() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n'
  fi
}

echo ""
echo "  TgWebProxyR · Docker Compose"
echo "  ────────────────────────────"
echo "  Нужны: DNS A-запись на этот сервер, открытые TCP 80/443"
echo ""

HOSTNAME="${TWPR_HOSTNAME:-}"
ACME_EMAIL="${TWPR_EMAIL:-}"
SECRET="${TWPR_SECRET:-}"

[[ -z "$HOSTNAME" ]] && ask HOSTNAME "Домен (hostname)"
[[ -z "$ACME_EMAIL" ]] && ask ACME_EMAIL "Email для Let's Encrypt"
[[ -z "$SECRET" ]] && SECRET="$(gen_secret)"

HOSTNAME="$(echo "$HOSTNAME" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
SECRET="$(echo "$SECRET" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

# подставляем hostname в стартовый сайт
if [[ -d "${ROOT}/site" ]]; then
  find "${ROOT}/site" -type f \( -name '*.html' -o -name '*.txt' \) -print0 2>/dev/null \
    | xargs -0 sed -i "s/__HOSTNAME__/${HOSTNAME}/g" 2>/dev/null || true
fi

umask 077
cat >"$ENV_FILE" <<EOF
TWPR_HOSTNAME=${HOSTNAME}
TWPR_EMAIL=${ACME_EMAIL}
TWPR_SECRET=${SECRET}
HTTP_PORT=${HTTP_PORT:-80}
HTTPS_PORT=${HTTPS_PORT:-443}
MTPROXY_WORKERS=${MTPROXY_WORKERS:-1}
MTPROXY_MAX_CONNECTIONS=${MTPROXY_MAX_CONNECTIONS:-4096}
TPROXY_REF=${TPROXY_REF:-master}
EOF
chmod 600 "$ENV_FILE"

echo ""
echo "  hostname : ${HOSTNAME}"
echo "  email    : ${ACME_EMAIL}"
echo "  secret   : ${SECRET}"
echo ""
echo "  >> docker compose up -d --build  (первая сборка MTProxy долгая)"
cd "$DOCKER_DIR"
docker compose --env-file "$ENV_FILE" up -d --build

echo ""
echo "  OK  стек поднят"
echo "  tg://webproxy?server=${HOSTNAME}&secret=${SECRET}"
echo "  https://t.me/webproxy?server=${HOSTNAME}&secret=${SECRET}"
echo ""
echo "  Логи:   cd ${DOCKER_DIR} && docker compose logs -f"
echo "  Стоп:   cd ${DOCKER_DIR} && docker compose down"
echo ""
