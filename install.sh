#!/usr/bin/env bash
# TgWebProxyR — one-liner bootstrap → сразу пошаговый мастер
#
#   wget -qO /tmp/tgwebproxyr-install.sh https://raw.githubusercontent.com/RasmusVraa/TgWebProxyR/main/install.sh && sudo bash /tmp/tgwebproxyr-install.sh
#   curl -fsSL https://raw.githubusercontent.com/RasmusVraa/TgWebProxyR/main/install.sh | sudo bash
set -euo pipefail

REPO="${TWPR_GITHUB_REPO:-RasmusVraa/TgWebProxyR}"
BRANCH="${TWPR_BRANCH:-main}"
INSTALL_DIR="/opt/tgwebproxyr"
SCRIPT_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
ARCHIVE_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"
INSTALL_LOG="/tmp/tgwebproxyr-bootstrap.log"

: >"$INSTALL_LOG"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Запустите от root:" >&2
  echo "  wget -qO /tmp/tgwebproxyr-install.sh ${SCRIPT_URL}/install.sh && sudo bash /tmp/tgwebproxyr-install.sh" >&2
  exit 1
fi

echo ""
echo "  TgWebProxyR — загрузка менеджера"
echo "  ────────────────────────────────"
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
find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 ! -name engine -exec rm -rf {} + 2>/dev/null || true
cp -a "${src}/." "${INSTALL_DIR}/"

# нормализуем переводы строк на случай CRLF
if command -v sed >/dev/null 2>&1; then
  find "$INSTALL_DIR" -type f \( -name '*.sh' -o -name 'version' \) -exec sed -i 's/\r$//' {} + 2>/dev/null || true
fi

chmod +x "${INSTALL_DIR}/tgwebproxyr.sh" "${INSTALL_DIR}/install.sh"
find "${INSTALL_DIR}/lib" -name '*.sh' -exec chmod +x {} \;

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
if [[ ! -t 0 ]] && [[ ! -r /dev/tty ]]; then
  echo "  XX Нет TTY для вопросов мастера."
  echo "     Запустите: sudo tgwebproxyr setup"
  exit 1
fi
echo "  Запускаю пошаговый мастер…"
sleep 1

# сразу полный wizard (Caddy + MTProxy + relay), без отдельных команд
exec /opt/tgwebproxyr/tgwebproxyr.sh setup
