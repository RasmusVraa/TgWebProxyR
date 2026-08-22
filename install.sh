#!/usr/bin/env bash
# TgWebProxyR — простой установщик
#
# Рекомендуется (есть TTY для вопросов):
#   wget -qO /tmp/twpr.sh https://raw.githubusercontent.com/RasmusVraa/TgWebProxyR/main/install.sh
#   sudo bash /tmp/twpr.sh
#
# Без вопросов (env):
#   sudo TWPR_HOSTNAME=proxy.example.com TWPR_EMAIL=you@example.com TWPR_YES=1 bash /tmp/twpr.sh
#
# Сразу Docker:
#   sudo bash /tmp/twpr.sh --docker
#
# Расширенный мастер:
#   sudo bash /tmp/twpr.sh --advanced
set -euo pipefail

REPO="${TWPR_GITHUB_REPO:-RasmusVraa/TgWebProxyR}"
BRANCH="${TWPR_BRANCH:-main}"
INSTALL_DIR="/opt/tgwebproxyr"
SCRIPT_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
ARCHIVE_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"
INSTALL_LOG="/tmp/tgwebproxyr-bootstrap.log"

# флаги
TWPR_SETUP_MODE="${TWPR_SETUP_MODE:-${TWPR_MODE:-}}"
for arg in "$@"; do
  case "$arg" in
    --quick|-q) TWPR_SETUP_MODE="quick" ;;
    --docker|-d) TWPR_SETUP_MODE="docker" ;;
    --advanced|-a) TWPR_SETUP_MODE="advanced" ;;
    --yes|-y) export TWPR_YES=1 ;;
    --help|-h)
      cat <<EOF
TgWebProxyR installer

  sudo bash install.sh              интерактивно (выбор режима)
  sudo bash install.sh --quick      быстро: домен + email
  sudo bash install.sh --docker     Docker Compose
  sudo bash install.sh --advanced   порты / workers / secret
  sudo bash install.sh --yes        не спрашивать подтверждение

Env: TWPR_HOSTNAME TWPR_EMAIL TWPR_SECRET TWPR_YES=1
EOF
      exit 0
      ;;
  esac
done
export TWPR_SETUP_MODE

: >"$INSTALL_LOG"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запустите от root:" >&2
  echo "  wget -qO /tmp/twpr.sh ${SCRIPT_URL}/install.sh && sudo bash /tmp/twpr.sh" >&2
  exit 1
fi

echo ""
echo "  ╔══════════════════════════════════════╗"
echo "  ║   TgWebProxyR — установка WEB-прокси ║"
echo "  ╚══════════════════════════════════════╝"
echo "  ${REPO} @ ${BRANCH}"
echo ""

if ! command -v curl >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq >>"$INSTALL_LOG" 2>&1
    apt-get install -y -qq curl ca-certificates >>"$INSTALL_LOG" 2>&1
  fi
fi

tmpdir="$(mktemp -d /tmp/tgwebproxyr-boot.XXXXXX)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

echo "  >> скачиваю исходники…"
if ! curl -fsSL --retry 4 --retry-delay 2 "$ARCHIVE_URL" -o "${tmpdir}/src.tgz" 2>>"$INSTALL_LOG"; then
  echo "  XX не удалось скачать ${ARCHIVE_URL}" >&2
  echo "  лог: ${INSTALL_LOG}" >&2
  exit 1
fi

mkdir -p "${tmpdir}/extract"
tar -xzf "${tmpdir}/src.tgz" -C "${tmpdir}/extract"
src="$(find "${tmpdir}/extract" -maxdepth 1 -type d -name 'TgWebProxyR-*' | head -1)"
[[ -n "$src" ]] || { echo "  XX архив пуст"; exit 1; }

mkdir -p "$INSTALL_DIR"
# не трогаем engine и docker volumes/state
find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 ! -name engine ! -name backups -exec rm -rf {} + 2>/dev/null || true
cp -a "${src}/." "${INSTALL_DIR}/"

if command -v sed >/dev/null 2>&1; then
  find "$INSTALL_DIR" -type f \( -name '*.sh' -o -name 'version' \) -exec sed -i 's/\r$//' {} + 2>/dev/null || true
fi

chmod +x "${INSTALL_DIR}/tgwebproxyr.sh" "${INSTALL_DIR}/install.sh"
find "${INSTALL_DIR}/lib" -name '*.sh' -exec chmod +x {} \;
find "${INSTALL_DIR}/docker" -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true
chmod +x "${INSTALL_DIR}/docker/entrypoint-"*.sh 2>/dev/null || true

cat >/usr/local/bin/tgwebproxyr <<'EOF'
#!/usr/bin/env bash
exec /opt/tgwebproxyr/tgwebproxyr.sh "$@"
EOF
chmod 0755 /usr/local/bin/tgwebproxyr
sed -i 's/\r$//' /usr/local/bin/tgwebproxyr 2>/dev/null || true

cat >/etc/profile.d/tgwebproxyr.sh <<'EOF'
alias tgwebproxyr='sudo tgwebproxyr'
EOF

VERSION="$(tr -d '[:space:]' </opt/tgwebproxyr/version 2>/dev/null || echo '?')"
echo ""
echo "  OK  менеджер v${VERSION} → ${INSTALL_DIR}"
echo "  OK  команда: tgwebproxyr"
echo ""

# полностью без TTY, но есть env — запускаем non-interactive
if [[ ! -t 0 ]] && [[ ! -r /dev/tty ]]; then
  if [[ -n "${TWPR_HOSTNAME:-}" && -n "${TWPR_EMAIL:-}" ]]; then
    export TWPR_YES="${TWPR_YES:-1}"
    export TWPR_SETUP_MODE="${TWPR_SETUP_MODE:-quick}"
    echo "  >> без TTY — ставлю по env (hostname/email)…"
    exec /opt/tgwebproxyr/tgwebproxyr.sh setup
  fi
  echo "  XX Нет TTY. Либо:"
  echo "     wget -qO /tmp/twpr.sh ${SCRIPT_URL}/install.sh && sudo bash /tmp/twpr.sh"
  echo "     sudo TWPR_HOSTNAME=… TWPR_EMAIL=… TWPR_YES=1 bash /tmp/twpr.sh"
  exit 1
fi

# подсказка перед мастером
if [[ -z "${TWPR_SETUP_MODE:-}" ]]; then
  echo "  Перед установкой подготовьте:"
  echo "    1. DNS A-запись домена → IP этого VPS"
  echo "    2. Открытые порты 80 и 443"
  echo ""
fi

exec env TWPR_SETUP_MODE="${TWPR_SETUP_MODE:-}" \
  TWPR_HOSTNAME="${TWPR_HOSTNAME:-}" \
  TWPR_EMAIL="${TWPR_EMAIL:-}" \
  TWPR_SECRET="${TWPR_SECRET:-}" \
  TWPR_YES="${TWPR_YES:-}" \
  /opt/tgwebproxyr/tgwebproxyr.sh setup
