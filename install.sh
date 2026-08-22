#!/usr/bin/env bash
# TgWebProxyR — bootstrap installer
#
# One-liner:
#   wget -qO /tmp/tgwebproxyr-install.sh https://raw.githubusercontent.com/RasmusVraa/TgWebProxyR/main/install.sh && sudo bash /tmp/tgwebproxyr-install.sh
#
# Or:
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
echo "  TgWebProxyR — установка менеджера"
echo "  ────────────────────────────────"
echo "  repo: ${REPO} @ ${BRANCH}"
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

echo "  ↓ скачиваю TgWebProxyR…"
if curl -fsSL --retry 4 --retry-delay 2 "$ARCHIVE_URL" -o "${tmpdir}/src.tgz" 2>>"$INSTALL_LOG"; then
  mkdir -p "${tmpdir}/extract"
  tar -xzf "${tmpdir}/src.tgz" -C "${tmpdir}/extract"
  src="$(find "${tmpdir}/extract" -maxdepth 1 -type d -name 'TgWebProxyR-*' | head -1)"
  [[ -n "$src" ]] || { echo "  ✗ архив пуст"; exit 1; }
else
  echo "  ✗ не удалось скачать ${ARCHIVE_URL}" >&2
  echo "  лог: ${INSTALL_LOG}" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
# Fresh tree without wiping host state outside INSTALL_DIR
find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 ! -name engine -exec rm -rf {} +
cp -a "${src}/." "${INSTALL_DIR}/"
rm -f "${INSTALL_DIR}/_ref_install.sh"

chmod +x "${INSTALL_DIR}/tgwebproxyr.sh" "${INSTALL_DIR}/install.sh"
find "${INSTALL_DIR}/lib" -name '*.sh' -exec chmod +x {} \;

cat >/usr/local/bin/tgwebproxyr <<'EOF'
#!/usr/bin/env bash
exec /opt/tgwebproxyr/tgwebproxyr.sh "$@"
EOF
chmod 0755 /usr/local/bin/tgwebproxyr

# Convenient alias for non-root shells
cat >/etc/profile.d/tgwebproxyr.sh <<'EOF'
alias tgwebproxyr='sudo tgwebproxyr'
EOF

VERSION="$(tr -d '[:space:]' </opt/tgwebproxyr/version 2>/dev/null || echo '?')"
echo ""
echo "  ✓ TgWebProxyR ${VERSION} установлен в ${INSTALL_DIR}"
echo "  ✓ команда: tgwebproxyr"
echo ""
echo "  Дальше:"
echo "    sudo tgwebproxyr setup"
echo ""

# Auto-enter setup unless skipped
if [[ "${TWPR_SKIP_SETUP:-0}" != "1" ]]; then
  exec /opt/tgwebproxyr/tgwebproxyr.sh setup
fi
