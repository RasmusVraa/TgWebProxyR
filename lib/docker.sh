#!/usr/bin/env bash
# TgWebProxyR — Docker Compose helpers (prefetch + GHCR pull)

TWPR_DOCKER_DIR="${TWPR_DOCKER_DIR:-${TWPR_ROOT}/docker}"
TWPR_IMAGE_TAG="${TWPR_IMAGE_TAG:-latest}"
TWPR_RELAY_IMAGE="${TWPR_RELAY_IMAGE:-ghcr.io/rasmusvraa/tgwebproxyr-relay}"
TWPR_MTPROXY_IMAGE="${TWPR_MTPROXY_IMAGE:-ghcr.io/rasmusvraa/tgwebproxyr-mtproxy}"
TWPR_CADDY_IMAGE="${TWPR_CADDY_IMAGE:-caddy:2.8-alpine}"

TWPR_docker_compose() {
  if ! command -v docker >/dev/null 2>&1; then
    TWPR_err "Docker не установлен"
    return 1
  fi
  if ! docker compose version >/dev/null 2>&1; then
    TWPR_err "Нужен Docker Compose v2: docker compose …"
    return 1
  fi
  (
    cd "$TWPR_DOCKER_DIR"
    export TWPR_IMAGE_TAG TWPR_RELAY_IMAGE TWPR_MTPROXY_IMAGE TWPR_CADDY_IMAGE
    docker compose --env-file "${TWPR_DOCKER_DIR}/.env" "$@"
  )
}

TWPR_docker_ensure_env() {
  local envf="${TWPR_DOCKER_DIR}/.env"
  if [[ -f "$envf" ]]; then
    # shellcheck disable=SC1090
    set -a
    # shellcheck disable=SC1091
    source "$envf"
    set +a
    TWPR_HOSTNAME="${TWPR_HOSTNAME:-${HOSTNAME:-}}"
    TWPR_EMAIL="${TWPR_EMAIL:-${ACME_EMAIL:-}}"
    TWPR_SECRET="${TWPR_SECRET:-${SECRET:-}}"
    TWPR_IMAGE_TAG="${TWPR_IMAGE_TAG:-latest}"
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
TWPR_IMAGE_TAG=${TWPR_IMAGE_TAG:-latest}
TWPR_RELAY_IMAGE=${TWPR_RELAY_IMAGE}
TWPR_MTPROXY_IMAGE=${TWPR_MTPROXY_IMAGE}
TWPR_CADDY_IMAGE=${TWPR_CADDY_IMAGE}
EOF
  chmod 600 "$envf"
}

# Параллельный pull — стартует сразу, не ждёт ответов пользователя
TWPR_docker_prefetch() {
  command -v docker >/dev/null 2>&1 || return 0
  local tag="${TWPR_IMAGE_TAG:-latest}"
  local log="/tmp/tgwebproxyr-docker-pull.log"
  : >"$log"
  TWPR_info "Параллельно качаю образы (Caddy + relay + mtproxy)…"
  (
    export DOCKER_CLI_HINTS=false
    pids=()
    docker pull "${TWPR_CADDY_IMAGE}" >>"$log" 2>&1 & pids+=($!)
    docker pull "${TWPR_RELAY_IMAGE}:${tag}" >>"$log" 2>&1 & pids+=($!)
    docker pull "${TWPR_MTPROXY_IMAGE}:${tag}" >>"$log" 2>&1 & pids+=($!)
    # если :latest ещё нет — пробуем версию из version
    if [[ "$tag" == "latest" ]]; then
      ver="$(tr -d '[:space:]' <"${TWPR_ROOT}/version" 2>/dev/null || true)"
      if [[ -n "$ver" ]]; then
        docker pull "${TWPR_RELAY_IMAGE}:${ver}" >>"$log" 2>&1 & pids+=($!)
        docker pull "${TWPR_MTPROXY_IMAGE}:${ver}" >>"$log" 2>&1 & pids+=($!)
      fi
    fi
    ec=0
    for p in "${pids[@]}"; do
      wait "$p" || ec=1
    done
    echo "$ec" >"${log}.ec"
  ) &
  TWPR_DOCKER_PREFETCH_PID=$!
  export TWPR_DOCKER_PREFETCH_PID
}

TWPR_docker_wait_prefetch() {
  if [[ -n "${TWPR_DOCKER_PREFETCH_PID:-}" ]]; then
    TWPR_info "Дожидаюсь окончания скачивания образов…"
    wait "${TWPR_DOCKER_PREFETCH_PID}" 2>/dev/null || true
    unset TWPR_DOCKER_PREFETCH_PID
  fi
}

TWPR_docker_images_ready() {
  local tag="${TWPR_IMAGE_TAG:-latest}"
  docker image inspect "${TWPR_RELAY_IMAGE}:${tag}" >/dev/null 2>&1 \
    && docker image inspect "${TWPR_MTPROXY_IMAGE}:${tag}" >/dev/null 2>&1 \
    && docker image inspect "${TWPR_CADDY_IMAGE}" >/dev/null 2>&1
}

TWPR_docker_ensure_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    return 0
  fi
  TWPR_info "Ставлю Docker…"
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker 2>/dev/null || true
  else
    TWPR_err "Установите Docker: https://docs.docker.com/engine/install/"
    return 1
  fi
  docker compose version >/dev/null 2>&1 || {
    TWPR_err "docker compose недоступен"
    return 1
  }
}

# pull-first; build только если образов нет
TWPR_docker_up() {
  TWPR_docker_wait_prefetch
  local tag="${TWPR_IMAGE_TAG:-latest}"
  local ver
  ver="$(tr -d '[:space:]' <"${TWPR_ROOT}/version" 2>/dev/null || echo "$tag")"

  TWPR_info "Тяну образы с GHCR (параллельно)…"
  set +e
  docker pull "${TWPR_CADDY_IMAGE}" >/dev/null 2>&1 &
  docker pull "${TWPR_RELAY_IMAGE}:${tag}" >/dev/null 2>&1 &
  docker pull "${TWPR_MTPROXY_IMAGE}:${tag}" >/dev/null 2>&1 &
  if [[ "$tag" == "latest" && -n "$ver" ]]; then
    docker pull "${TWPR_RELAY_IMAGE}:${ver}" >/dev/null 2>&1 &
    docker pull "${TWPR_MTPROXY_IMAGE}:${ver}" >/dev/null 2>&1 &
  fi
  wait
  set -e

  if TWPR_docker_images_ready && [[ "${TWPR_DOCKER_BUILD:-0}" != "1" ]]; then
    TWPR_ok "Образы GHCR на месте — up без сборки"
    TWPR_docker_compose up -d --no-build --remove-orphans
    return $?
  fi

  # Быстрый fallback: docker build только скачивает бинарники с Releases (~десятки секунд)
  TWPR_warn "GHCR недоступен — быстрая сборка из release-бинарников v${ver}"
  export DOCKER_BUILDKIT=1 COMPOSE_DOCKER_CLI_BUILD=1
  TWPR_IMAGE_TAG="$ver"
  # подставим версию в .env для build-args
  if [[ -f "${TWPR_DOCKER_DIR}/.env" ]]; then
    grep -q '^TWPR_IMAGE_TAG=' "${TWPR_DOCKER_DIR}/.env" \
      && sed -i "s/^TWPR_IMAGE_TAG=.*/TWPR_IMAGE_TAG=${ver}/" "${TWPR_DOCKER_DIR}/.env" \
      || echo "TWPR_IMAGE_TAG=${ver}" >>"${TWPR_DOCKER_DIR}/.env"
  fi
  TWPR_docker_compose build --parallel \
    --build-arg "TWPR_VERSION=${ver}"
  TWPR_docker_compose up -d --remove-orphans
}

TWPR_docker_install_engine() {
  TWPR_require_root
  TWPR_banner
  echo "  Установка через Docker Compose"
  echo "  Готовые образы GHCR → быстрый старт"
  echo ""

  TWPR_docker_ensure_docker || return 1
  TWPR_ok "Docker готов"

  # сразу качаем, пока пользователь отвечает на вопросы
  TWPR_IMAGE_TAG="${TWPR_IMAGE_TAG:-latest}"
  TWPR_docker_prefetch

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

  TWPR_info "Собираю и поднимаю контейнеры…"
  # сбросить старые контейнеры с другой схемой сети
  TWPR_docker_compose down --remove-orphans 2>/dev/null || true
  TWPR_docker_up || {
    TWPR_err "Не удалось поднять стек. Лог pull: /tmp/tgwebproxyr-docker-pull.log"
    TWPR_docker_compose logs --tail=80 || true
    return 1
  }

  echo ""
  TWPR_ok "Docker-стек запущен"
  TWPR_cmd_link
  echo ""
  TWPR_info "Управление:  tgwebproxyr docker status|logs|down|up"
}

TWPR_cmd_docker() {
  local sub="${1:-}"
  shift || true
  case "$sub" in
    setup|install)
      TWPR_load_state
      TWPR_docker_install_engine
      ;;
    up)
      if [[ ! -f "${TWPR_DOCKER_DIR}/.env" ]]; then
        TWPR_load_state
        TWPR_docker_install_engine
      else
        TWPR_docker_ensure_env || true
        TWPR_docker_up
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
        TWPR_cmd_link 2>/dev/null || true
      fi
      ;;
    link)
      TWPR_load_state
      TWPR_docker_ensure_env || true
      TWPR_cmd_link
      ;;
    pull)
      TWPR_docker_prefetch
      TWPR_docker_wait_prefetch
      TWPR_docker_compose pull "$@"
      ;;
    build)
      export DOCKER_BUILDKIT=1 TWPR_DOCKER_BUILD=1
      TWPR_docker_compose build --parallel "$@"
      ;;
    *)
      cat <<EOF
Использование: tgwebproxyr docker <команда>

  setup     Docker + параллельный pull GHCR + подъём стека
  up        pull (если нужно) и up -d
  down      остановить
  restart   перезапуск
  status    статус
  logs      логи
  link      ссылки
  pull      обновить образы
  build     локальная сборка (медленно)

Образы: ${TWPR_RELAY_IMAGE}:${TWPR_IMAGE_TAG}
        ${TWPR_MTPROXY_IMAGE}:${TWPR_IMAGE_TAG}
Каталог: ${TWPR_DOCKER_DIR}
EOF
      ;;
  esac
}
