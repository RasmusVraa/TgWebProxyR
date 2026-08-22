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
  local -a comp_args=(--env-file "${TWPR_DOCKER_DIR}/.env" -f docker-compose.yml)
  if [[ -f "${TWPR_DOCKER_DIR}/docker-compose.tls.yml" ]]; then
    comp_args+=(-f docker-compose.tls.yml)
  fi
  (
    cd "$TWPR_DOCKER_DIR"
    export TWPR_IMAGE_TAG TWPR_RELAY_IMAGE TWPR_MTPROXY_IMAGE TWPR_CADDY_IMAGE
    docker compose "${comp_args[@]}" "$@"
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
MTPROXY_NAT_INFO=${TWPR_MTPROXY_NAT_INFO:-}
MTPROXY_EXTERNAL_IP=${TWPR_PUBLIC_IP:-}
MTPROXY_INTERNAL_IP=${TWPR_MTPROXY_INTERNAL_IP:-}
TPROXY_REF=${TWPR_ENGINE_REF:-master}
TWPR_IMAGE_TAG=${TWPR_IMAGE_TAG:-latest}
TWPR_RELAY_IMAGE=${TWPR_RELAY_IMAGE}
TWPR_MTPROXY_IMAGE=${TWPR_MTPROXY_IMAGE}
TWPR_CADDY_IMAGE=${TWPR_CADDY_IMAGE}
EOF
  chmod 600 "$envf"
}

TWPR_docker_pull_one() {
  # TWPR_docker_pull_one NAME IMAGE → пишет лог /tmp/twpr-pull-NAME.log, pid в .pid
  local name="$1" image="$2"
  local log="/tmp/twpr-pull-${name}.log"
  local pidf="/tmp/twpr-pull-${name}.pid"
  : >"$log"
  (
    export DOCKER_CLI_HINTS=false
    # line-buffered, чтобы прогресс сразу в лог
    if command -v stdbuf >/dev/null 2>&1; then
      stdbuf -oL -eL docker pull "$image" >>"$log" 2>&1
    else
      docker pull "$image" >>"$log" 2>&1
    fi
    echo "EXIT:$?" >>"$log"
  ) &
  echo $! >"$pidf"
}

TWPR_docker_pull_tail() {
  # последняя осмысленная строка прогресса
  local log="$1" line
  line="$(grep -E 'Downloading|Extracting|Pull complete|Already exists|Download complete|Pulling from|EXIT:|denied|Error|not found' "$log" 2>/dev/null | tail -1 || true)"
  [[ -z "$line" ]] && line="$(tail -1 "$log" 2>/dev/null || true)"
  # укоротить
  line="${line#"${line%%[![:space:]]*}"}"
  if [[ ${#line} -gt 64 ]]; then
    line="${line:0:61}…"
  fi
  printf '%s' "${line:-…}"
}

TWPR_docker_pull_bar() {
  local done="$1" total="$2" i bar="" filled=0
  [[ "$total" -lt 1 ]] && total=1
  filled=$(( done * 20 / total ))
  for ((i = 0; i < 20; i++)); do
    if (( i < filled )); then bar+="#"; else bar+="-"; fi
  done
  printf '[%s] %s/%s' "$bar" "$done" "$total"
}

# Параллельный pull с живым прогрессом на экране
TWPR_docker_pull_images() {
  command -v docker >/dev/null 2>&1 || return 1
  local tag="${TWPR_IMAGE_TAG:-latest}"
  local ver
  ver="$(tr -d '[:space:]' <"${TWPR_ROOT}/version" 2>/dev/null || echo "$tag")"

  local -a names=() images=()
  names+=(caddy); images+=("${TWPR_CADDY_IMAGE}")
  names+=(relay); images+=("${TWPR_RELAY_IMAGE}:${tag}")
  names+=(mtproxy); images+=("${TWPR_MTPROXY_IMAGE}:${tag}")
  if [[ "$tag" == "latest" && -n "$ver" && "$ver" != "latest" ]]; then
    names+=(relay-ver); images+=("${TWPR_RELAY_IMAGE}:${ver}")
    names+=(mtproxy-ver); images+=("${TWPR_MTPROXY_IMAGE}:${ver}")
  fi

  local n=${#names[@]} i
  echo ""
  TWPR_info "Скачиваю Docker-образы (${n} шт., параллельно)…"
  echo -e "  ${C_DIM}обычно 1–3 минуты на чистом VPS — сейчас будет прогресс${C_RESET}"
  echo ""

  for ((i = 0; i < n; i++)); do
    TWPR_docker_pull_one "${names[$i]}" "${images[$i]}"
  done

  local show_n=3
  (( n < 3 )) && show_n=$n

  # резерв строк под UI
  echo "  [--------------------] 0/${n}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
  local _r
  for ((_r = 0; _r < show_n; _r++)); do echo "  …"; done

  local finished=0 spin='|/-\' si=0 started
  started=$(date +%s)

  while (( finished < n )); do
    finished=0
    local -a lines=()
    for ((i = 0; i < n; i++)); do
      local name="${names[$i]}"
      local pidf="/tmp/twpr-pull-${name}.pid"
      local log="/tmp/twpr-pull-${name}.log"
      local pid="" st="…"
      [[ -f "$pidf" ]] && pid="$(cat "$pidf" 2>/dev/null || true)"
      if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        st="$(TWPR_docker_pull_tail "$log")"
      else
        finished=$((finished + 1))
        if grep -q 'EXIT:0' "$log" 2>/dev/null || docker image inspect "${images[$i]}" >/dev/null 2>&1; then
          st="OK готово"
        else
          st="!! пропуск"
        fi
      fi
      if (( i < show_n )); then
        local label="${names[$i]}"
        printf -v label '%-8s' "$label"
        lines+=("  ${label} ${st}")
      fi
    done

    local elapsed=$(( $(date +%s) - started ))
    local spin_c="${spin:$((si % 4)):1}"
    si=$((si + 1))

    printf '\033[%dA' "$((show_n + 2))"
    printf '\033[2K\r  %s  %s  %ss\n' "$(TWPR_docker_pull_bar "$finished" "$n")" "$spin_c" "$elapsed"
    printf '\033[2K\r  %s\n' "${C_GRAY}────────────────────────────────────────${C_RESET}"
    local L
    for L in "${lines[@]}"; do
      printf '\033[2K\r%s\n' "$L"
    done

    (( finished >= n )) && break
    sleep 1
  done

  echo ""
  local okc=0
  for ((i = 0; i < show_n; i++)); do
    local name="${names[$i]}" log="/tmp/twpr-pull-${name}.log"
    if grep -q 'EXIT:0' "$log" 2>/dev/null || docker image inspect "${images[$i]}" >/dev/null 2>&1; then
      TWPR_ok "${names[$i]}  ${images[$i]}"
      okc=$((okc + 1))
    else
      TWPR_warn "${names[$i]}  не скачался (будет сборка из Releases)"
    fi
  done
  echo ""
  [[ "$okc" -ge 1 ]]
}

# Параллельный pull — в фоне на этапе вопросов (с тихим логом + heartbeat)
TWPR_docker_prefetch() {
  command -v docker >/dev/null 2>&1 || return 0
  local tag="${TWPR_IMAGE_TAG:-latest}"
  local logdir="/tmp/twpr-prefetch"
  mkdir -p "$logdir"
  TWPR_info "В фоне уже качаю образы (пока отвечаете на вопросы)…"
  (
    export DOCKER_CLI_HINTS=false
    TWPR_docker_pull_one caddy "${TWPR_CADDY_IMAGE}"
    TWPR_docker_pull_one relay "${TWPR_RELAY_IMAGE}:${tag}"
    TWPR_docker_pull_one mtproxy "${TWPR_MTPROXY_IMAGE}:${tag}"
    local ver
    ver="$(tr -d '[:space:]' <"${TWPR_ROOT}/version" 2>/dev/null || true)"
    if [[ "$tag" == "latest" && -n "$ver" ]]; then
      TWPR_docker_pull_one relay-ver "${TWPR_RELAY_IMAGE}:${ver}"
      TWPR_docker_pull_one mtproxy-ver "${TWPR_MTPROXY_IMAGE}:${ver}"
    fi
    # heartbeat в общий лог
    local hb="/tmp/tgwebproxyr-docker-pull.log"
    : >"$hb"
    while true; do
      local any=0 name
      for name in caddy relay mtproxy relay-ver mtproxy-ver; do
        local pidf="/tmp/twpr-pull-${name}.pid"
        local pid=""
        [[ -f "$pidf" ]] && pid="$(cat "$pidf" 2>/dev/null || true)"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
          any=1
          echo "[$(date +%H:%M:%S)] $name: $(TWPR_docker_pull_tail /tmp/twpr-pull-${name}.log)" >>"$hb"
        fi
      done
      (( any == 0 )) && break
      sleep 2
    done
    wait || true
    echo 0 >"${hb}.ec"
  ) &
  TWPR_DOCKER_PREFETCH_PID=$!
  export TWPR_DOCKER_PREFETCH_PID
}

TWPR_docker_wait_prefetch() {
  if [[ -z "${TWPR_DOCKER_PREFETCH_PID:-}" ]]; then
    return 0
  fi
  TWPR_info "Дожидаюсь фонового скачивания…"
  # пока ждём — показываем прогресс из логов
  local spin='|/-\' si=0
  while kill -0 "${TWPR_DOCKER_PREFETCH_PID}" 2>/dev/null; do
    local caddy_st relay_st mp_st
    caddy_st="$(TWPR_docker_pull_tail /tmp/twpr-pull-caddy.log 2>/dev/null || echo …)"
    relay_st="$(TWPR_docker_pull_tail /tmp/twpr-pull-relay.log 2>/dev/null || echo …)"
    mp_st="$(TWPR_docker_pull_tail /tmp/twpr-pull-mtproxy.log 2>/dev/null || echo …)"
    printf '\r\033[2K  %s  caddy: %-28s | relay: %-28s | mtproxy: %-28s' \
      "${spin:$((si % 4)):1}" "${caddy_st:0:28}" "${relay_st:0:28}" "${mp_st:0:28}"
    si=$((si + 1))
    sleep 1
  done
  echo ""
  wait "${TWPR_DOCKER_PREFETCH_PID}" 2>/dev/null || true
  unset TWPR_DOCKER_PREFETCH_PID
  TWPR_ok "Фоновое скачивание завершено"
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
  TWPR_info "Ставлю Docker (лог: /tmp/tgwebproxyr-bootstrap.log)…"
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

  # если образов ещё нет — тянем с прогрессом
  if ! TWPR_docker_images_ready; then
    TWPR_IMAGE_TAG="$tag"
    TWPR_docker_pull_images || true
  else
    TWPR_ok "Образы уже на диске"
  fi

  if TWPR_docker_images_ready && [[ "${TWPR_DOCKER_BUILD:-0}" != "1" ]]; then
    TWPR_ok "Поднимаю контейнеры…"
    TWPR_docker_compose up -d --no-build --remove-orphans
  else
    TWPR_warn "GHCR недоступен — быстрая сборка из release-бинарников v${ver}"
    export DOCKER_BUILDKIT=1 COMPOSE_DOCKER_CLI_BUILD=1
    TWPR_IMAGE_TAG="$ver"
    if [[ -f "${TWPR_DOCKER_DIR}/.env" ]]; then
      grep -q '^TWPR_IMAGE_TAG=' "${TWPR_DOCKER_DIR}/.env" \
        && sed -i "s/^TWPR_IMAGE_TAG=.*/TWPR_IMAGE_TAG=${ver}/" "${TWPR_DOCKER_DIR}/.env" \
        || echo "TWPR_IMAGE_TAG=${ver}" >>"${TWPR_DOCKER_DIR}/.env"
    fi
    TWPR_info "docker compose build (скачивание бинарников)…"
    TWPR_docker_compose build --progress=plain --parallel --build-arg "TWPR_VERSION=${ver}"
    TWPR_docker_compose up -d --remove-orphans
  fi

  TWPR_info "Жду готовности relay…"
  local i hz="down"
  for i in $(seq 1 45); do
    sleep 2
    hz="$(TWPR_health_probe 2>/dev/null || echo down)"
    printf '\r\033[2K  health… %ss  (%s)' "$((i * 2))" "$hz"
    [[ "$hz" == "ready" || "$hz" == "alive" ]] && break
  done
  echo ""
  case "$hz" in
    ready) TWPR_ok "Стек ready" ;;
    alive) TWPR_warn "Стек alive, backend ещё прогревается" ;;
    *)     TWPR_warn "Стек поднят, но health пока down — tgwebproxyr docker logs" ;;
  esac
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

  TWPR_certs_probe_and_choose

  if [[ "${TWPR_TLS_MODE:-acme}" != "file" ]]; then
    if [[ -z "${TWPR_EMAIL:-}" ]]; then
      while true; do
        TWPR_ask TWPR_EMAIL "Email для Let's Encrypt"
        TWPR_validate_email "$TWPR_EMAIL" && break
        TWPR_warn "Некорректный email"
      done
    fi
  else
    TWPR_EMAIL="${TWPR_EMAIL:-admin@$(TWPR_certs_normalize_host "$TWPR_HOSTNAME")}"
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
  TWPR_certs_prepare_docker
  TWPR_docker_write_env
  TWPR_save_state
  # файл нужен до compose up (bind-mount; иначе Docker создаст каталог)
  TWPR_ensure_default_profile 2>/dev/null || true

  TWPR_info "Собираю и поднимаю контейнеры…"
  # не -v: сохраняем caddy_data (уже выпущенные ACME-серты Caddy)
  TWPR_docker_compose down --remove-orphans 2>/dev/null || true
  TWPR_docker_up || {
    TWPR_err "Не удалось поднять стек. Лог pull: /tmp/tgwebproxyr-docker-pull.log"
    TWPR_docker_compose logs --tail=80 || true
    return 1
  }

  echo ""
  TWPR_ok "Docker-стек запущен"
  # закрепим DEPLOY_MODE=docker в settings (на случай старых установок)
  TWPR_DEPLOY_MODE="docker"
  TWPR_save_state
  TWPR_cmd_status
  echo ""
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
      TWPR_docker_pull_images
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
