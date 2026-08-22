#!/usr/bin/env bash
# TgWebProxyR — Docker Compose helpers

TWPR_DOCKER_DIR="${TWPR_DOCKER_DIR:-${TWPR_ROOT}/docker}"

TWPR_docker_compose() {
  if ! command -v docker >/dev/null 2>&1; then
    TWPR_err "Docker не установлен"
    return 1
  fi
  if ! docker compose version >/dev/null 2>&1; then
    TWPR_err "Нужен Docker Compose v2: docker compose …"
    return 1
  fi
  (cd "$TWPR_DOCKER_DIR" && docker compose --env-file "${TWPR_DOCKER_DIR}/.env" "$@")
}

TWPR_docker_ensure_env() {
  local envf="${TWPR_DOCKER_DIR}/.env"
  if [[ -f "$envf" ]]; then
    # shellcheck disable=SC1090
    set -a
    # shellcheck disable=SC1091
    source "$envf"
    set +a
    # поддержка старого .env с HOSTNAME=/SECRET=
    TWPR_HOSTNAME="${TWPR_HOSTNAME:-${HOSTNAME:-}}"
    TWPR_EMAIL="${TWPR_EMAIL:-${ACME_EMAIL:-}}"
    TWPR_SECRET="${TWPR_SECRET:-${SECRET:-}}"
    return 0
  fi
  return 1
}

TWPR_docker_write_env() {
  local envf="${TWPR_DOCKER_DIR}/.env"
  umask 077
  cat >"$envf" <<EOF
TWPR_HOSTNAME=${TWPR_HOSTNAME}
TWPR_EMAIL=${TWPR_EMAIL}
TWPR_SECRET=${TWPR_SECRET}
HTTP_PORT=${TWPR_PORT_HTTP:-80}
HTTPS_PORT=${TWPR_PORT_HTTPS:-443}
MTPROXY_WORKERS=${TWPR_MTPROXY_WORKERS:-1}
MTPROXY_MAX_CONNECTIONS=${TWPR_MTPROXY_MAX_CONNECTIONS:-4096}
TPROXY_REF=${TWPR_ENGINE_REF:-master}
EOF
  chmod 600 "$envf"
}

TWPR_docker_install_engine() {
  TWPR_require_root
  TWPR_banner
  echo "  Установка через Docker Compose"
  echo "  Caddy + tproxy-server + MTProxy в контейнерах"
  echo ""

  if ! command -v docker >/dev/null 2>&1; then
    TWPR_info "Ставлю Docker…"
    if command -v apt-get >/dev/null 2>&1; then
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -qq
      apt-get install -y -qq ca-certificates curl
      curl -fsSL https://get.docker.com | sh
      systemctl enable --now docker 2>/dev/null || true
    else
      TWPR_err "Установите Docker вручную: https://docs.docker.com/engine/install/"
      return 1
    fi
  fi
  if ! docker compose version >/dev/null 2>&1; then
    TWPR_err "docker compose недоступен после установки Docker"
    return 1
  fi
  TWPR_ok "Docker готов"

  # быстрые вопросы: только домен + email
  if [[ -z "${TWPR_HOSTNAME:-}" ]]; then
    while true; do
      TWPR_ask TWPR_HOSTNAME "Домен (hostname)"
      TWPR_HOSTNAME="$(echo "$TWPR_HOSTNAME" | tr '[:upper:]' '[:lower:]')"
      TWPR_validate_hostname "$TWPR_HOSTNAME" && break
      TWPR_warn "Пример: proxy.example.com"
    done
  fi
  if [[ -z "${TWPR_EMAIL:-}" ]]; then
    while true; do
      TWPR_ask TWPR_EMAIL "Email для Let's Encrypt"
      TWPR_validate_email "$TWPR_EMAIL" && break
      TWPR_warn "Некорректный email"
    done
  fi
  if [[ -z "${TWPR_SECRET:-}" ]]; then
    TWPR_SECRET="$(TWPR_gen_secret)"
    TWPR_ok "Secret сгенерирован автоматически"
  fi

  TWPR_PORT_HTTP="${TWPR_PORT_HTTP:-80}"
  TWPR_PORT_HTTPS="${TWPR_PORT_HTTPS:-443}"
  TWPR_MTPROXY_WORKERS="${TWPR_MTPROXY_WORKERS:-1}"
  TWPR_MTPROXY_MAX_CONNECTIONS="${TWPR_MTPROXY_MAX_CONNECTIONS:-4096}"
  TWPR_DEPLOY_MODE="docker"
  TWPR_INSTALLED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  TWPR_prepare_site
  TWPR_docker_write_env
  TWPR_save_state

  TWPR_info "Собираю и поднимаю контейнеры (первая сборка MTProxy — несколько минут)…"
  TWPR_docker_compose up -d --build

  echo ""
  TWPR_ok "Docker-стек запущен"
  TWPR_cmd_link
  echo ""
  TWPR_info "Управление:  tgwebproxyr docker status|logs|down|up"
  TWPR_info "Или:         cd ${TWPR_DOCKER_DIR} && docker compose …"
}

TWPR_cmd_docker() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    setup|install|up)
      if [[ "$sub" == "up" ]] && [[ -f "${TWPR_DOCKER_DIR}/.env" ]]; then
        TWPR_docker_compose up -d "$@"
      else
        TWPR_load_state
        TWPR_docker_install_engine
      fi
      ;;
    down|stop)
      TWPR_docker_compose down "$@"
      ;;
    restart)
      TWPR_docker_compose restart "$@"
      ;;
    logs)
      TWPR_docker_compose logs -f --tail=100 "$@"
      ;;
    status|ps)
      TWPR_docker_compose ps "$@"
      echo ""
      if TWPR_docker_ensure_env; then
        curl -fsS --max-time 3 http://127.0.0.1:8081/healthz 2>/dev/null \
          && TWPR_ok "relay healthz OK" || TWPR_warn "relay healthz недоступен с хоста (нормально, если порт не проброшен)"
        TWPR_cmd_link 2>/dev/null || true
      fi
      ;;
    link)
      TWPR_load_state
      TWPR_docker_ensure_env || true
      TWPR_cmd_link
      ;;
    pull|build)
      TWPR_docker_compose build --pull "$@"
      ;;
    *)
      cat <<EOF
Использование: tgwebproxyr docker <команда>

  setup     установить Docker (если нужно) + поднять стек (2 вопроса)
  up        docker compose up -d
  down      остановить стек
  restart   перезапуск
  status    статус контейнеров
  logs      логи
  link      ссылки для Telegram
  build     пересобрать образы

Каталог: ${TWPR_DOCKER_DIR}
EOF
      ;;
  esac
}
