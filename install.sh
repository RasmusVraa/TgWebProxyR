#!/usr/bin/env bash
# TgWebProxyR — Docker-only installer
#
#   wget -qO /tmp/twpr.sh https://raw.githubusercontent.com/RasmusVraa/TgWebProxyR/main/install.sh
#   sudo bash /tmp/twpr.sh
#
# Env: TWPR_HOSTNAME TWPR_EMAIL TWPR_SECRET TWPR_YES=1
set -euo pipefail

REPO="${TWPR_GITHUB_REPO:-RasmusVraa/TgWebProxyR}"
BRANCH="${TWPR_BRANCH:-main}"
INSTALL_DIR="/opt/tgwebproxyr"
SCRIPT_URL="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
ARCHIVE_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"
INSTALL_LOG="/tmp/tgwebproxyr-bootstrap.log"
export TWPR_SETUP_MODE=docker

for arg in "$@"; do
  case "$arg" in
    --yes|-y) export TWPR_YES=1 ;;
    --help|-h)
      cat <<EOF
TgWebProxyR — установка только через Docker

  sudo bash install.sh
  sudo TWPR_HOSTNAME=proxy.example.com TWPR_EMAIL=you@ex.com TWPR_YES=1 bash install.sh
EOF
      exit 0
      ;;
  esac
done

: >"$INSTALL_LOG"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Нужен root:" >&2
  echo "  wget -qO /tmp/twpr.sh ${SCRIPT_URL}/install.sh && sudo bash /tmp/twpr.sh" >&2
  exit 1
fi

echo ""
echo "  TgWebProxyR · Docker"
echo "  ────────────────────"
echo "  ${REPO} @ ${BRANCH}"
echo ""

export DEBIAN_FRONTEND=noninteractive
if ! command -v curl >/dev/null 2>&1; then
  apt-get update -qq >>"$INSTALL_LOG" 2>&1 || true
  apt-get install -y -qq curl ca-certificates >>"$INSTALL_LOG" 2>&1 || true
fi

# Docker сразу в фоне (прогресс — при ожидании в setup)
echo "  >> Docker + образы в фоне…"
(
  if ! command -v docker >/dev/null 2>&1; then
    echo "[bootstrap] installing docker…" >>"$INSTALL_LOG"
    curl -fsSL https://get.docker.com | sh >>"$INSTALL_LOG" 2>&1 || true
    systemctl enable --now docker >>"$INSTALL_LOG" 2>&1 || true
  fi
  if command -v docker >/dev/null 2>&1; then
    export DOCKER_CLI_HINTS=false
    for img in caddy:2.8-alpine \
      ghcr.io/rasmusvraa/tgwebproxyr-relay:latest \
      ghcr.io/rasmusvraa/tgwebproxyr-mtproxy:latest; do
      name="$(echo "$img" | tr '/:' '__')"
      log="/tmp/twpr-boot-pull-${name}.log"
      ( stdbuf -oL docker pull "$img" >"$log" 2>&1 || docker pull "$img" >"$log" 2>&1
        echo "EXIT:$?" >>"$log" ) &
      echo $! >"/tmp/twpr-boot-pull-${name}.pid"
    done
    # heartbeat
    while true; do
      any=0
      for pidf in /tmp/twpr-boot-pull-*.pid; do
        [[ -f "$pidf" ]] || continue
        pid="$(cat "$pidf" 2>/dev/null || true)"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
          any=1
          log="${pidf%.pid}.log"
          line="$(tail -1 "$log" 2>/dev/null | tr -d '\r' | cut -c1-80)"
          echo "[$(date +%H:%M:%S)] ${line}" >>"$INSTALL_LOG"
        fi
      done
      [[ "$any" -eq 0 ]] && break
      sleep 3
    done
    wait || true
  fi
) &
EARLY_PID=$!
echo "  >> (прогресс образов: tail -f ${INSTALL_LOG})"

tmpdir="$(mktemp -d /tmp/tgwebproxyr-boot.XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

echo "  >> исходники…"
curl -fsSL --retry 4 --retry-delay 2 "$ARCHIVE_URL" -o "${tmpdir}/src.tgz" 2>>"$INSTALL_LOG"
mkdir -p "${tmpdir}/extract"
tar -xzf "${tmpdir}/src.tgz" -C "${tmpdir}/extract"
src="$(find "${tmpdir}/extract" -maxdepth 1 -type d -name 'TgWebProxyR-*' | head -1)"
[[ -n "$src" ]] || { echo "  XX пустой архив"; exit 1; }

mkdir -p "$INSTALL_DIR"
find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 ! -name engine ! -name backups ! -name docker -exec rm -rf {} + 2>/dev/null || true
# сохранить docker/.env если был
if [[ -f "${INSTALL_DIR}/docker/.env" ]]; then
  cp -a "${INSTALL_DIR}/docker/.env" "${tmpdir}/.env.save"
fi
cp -a "${src}/." "${INSTALL_DIR}/"
if [[ -f "${tmpdir}/.env.save" ]]; then
  mkdir -p "${INSTALL_DIR}/docker"
  cp -a "${tmpdir}/.env.save" "${INSTALL_DIR}/docker/.env"
fi

find "$INSTALL_DIR" -type f \( -name '*.sh' -o -name 'version' \) -exec sed -i 's/\r$//' {} + 2>/dev/null || true
chmod +x "${INSTALL_DIR}/tgwebproxyr.sh" "${INSTALL_DIR}/install.sh"
find "${INSTALL_DIR}/lib" -name '*.sh' -exec chmod +x {} \;
find "${INSTALL_DIR}/docker" -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true

cat >/usr/local/bin/tgwebproxyr <<'EOF'
#!/usr/bin/env bash
exec /opt/tgwebproxyr/tgwebproxyr.sh "$@"
EOF
chmod 0755 /usr/local/bin/tgwebproxyr

VERSION="$(tr -d '[:space:]' </opt/tgwebproxyr/version 2>/dev/null || echo '?')"
echo "  OK  v${VERSION} → ${INSTALL_DIR}"

# дождаться фона с коротким прогрессом
if kill -0 "$EARLY_PID" 2>/dev/null; then
  echo "  >> жду Docker/образы…"
  spin='|/-\' si=0
  while kill -0 "$EARLY_PID" 2>/dev/null; do
    line="$(tail -1 "$INSTALL_LOG" 2>/dev/null | tr -d '\r' | cut -c1-70)"
    printf '\r\033[2K  %s  %s' "${spin:$((si % 4)):1}" "${line:-качаю…}"
    si=$((si + 1))
    sleep 1
  done
  echo ""
fi
wait "$EARLY_PID" 2>/dev/null || true

if [[ ! -r /dev/tty ]] && [[ ! -t 0 ]]; then
  if [[ -n "${TWPR_HOSTNAME:-}" && -n "${TWPR_EMAIL:-}" ]]; then
    export TWPR_YES=1 TWPR_SETUP_MODE=docker
    exec /opt/tgwebproxyr/tgwebproxyr.sh setup
  fi
  echo "  XX Нет TTY. Запустите файл через bash, не curl|bash"
  exit 1
fi

echo ""
echo "  Нужны DNS A на этот VPS и порты 80/443"
echo ""
exec env TWPR_SETUP_MODE=docker \
  TWPR_HOSTNAME="${TWPR_HOSTNAME:-}" \
  TWPR_EMAIL="${TWPR_EMAIL:-}" \
  TWPR_SECRET="${TWPR_SECRET:-}" \
  TWPR_YES="${TWPR_YES:-}" \
  /opt/tgwebproxyr/tgwebproxyr.sh setup
