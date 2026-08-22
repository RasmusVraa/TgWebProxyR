#!/usr/bin/env bash
# TgWebProxyR — status, health, links

TWPR_docker_container_state() {
  # имя compose-сервиса → running|unhealthy|exited|missing
  local svc="$1" id st health
  id="$(docker compose -f "${TWPR_ROOT}/docker/docker-compose.yml" \
        --env-file "${TWPR_ROOT}/docker/.env" ps -q "$svc" 2>/dev/null | head -1 || true)"
  if [[ -z "$id" ]]; then
    echo "missing"
    return
  fi
  st="$(docker inspect -f '{{.State.Status}}' "$id" 2>/dev/null || echo missing)"
  health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{end}}' "$id" 2>/dev/null || true)"
  if [[ "$st" == "running" && "$health" == "unhealthy" ]]; then
    echo "unhealthy"
  elif [[ "$st" == "running" ]]; then
    echo "running"
  else
    echo "${st:-missing}"
  fi
}

TWPR_fmt_svc() {
  local name="$1" st="$2"
  case "$st" in
    running|active) echo -e "${C_GREEN}${name}${C_RESET}" ;;
    unhealthy|inactive) echo -e "${C_YELLOW}${name}:${st}${C_RESET}" ;;
    *) echo -e "${C_RED}${name}:${st}${C_RESET}" ;;
  esac
}

TWPR_health_probe() {
  # печатает: ready | alive | down
  local admin="${TWPR_PORT_ADMIN:-8081}"
  if curl -fsS --max-time 2 "http://127.0.0.1:${admin}/readyz" >/dev/null 2>&1; then
    echo ready
    return 0
  fi
  if curl -fsS --max-time 2 "http://127.0.0.1:${admin}/healthz" >/dev/null 2>&1; then
    echo alive
    return 0
  fi
  if TWPR_is_docker 2>/dev/null; then
    if docker compose -f "${TWPR_ROOT}/docker/docker-compose.yml" \
         --env-file "${TWPR_ROOT}/docker/.env" \
         exec -T relay curl -fsS --max-time 3 http://127.0.0.1:8081/readyz >/dev/null 2>&1; then
      echo ready
      return 0
    fi
    if docker compose -f "${TWPR_ROOT}/docker/docker-compose.yml" \
         --env-file "${TWPR_ROOT}/docker/.env" \
         exec -T relay curl -fsS --max-time 3 http://127.0.0.1:8081/healthz >/dev/null 2>&1; then
      echo alive
      return 0
    fi
    # relay в network_mode service:mtproxy — пробуем через mtproxy
    if docker compose -f "${TWPR_ROOT}/docker/docker-compose.yml" \
         --env-file "${TWPR_ROOT}/docker/.env" \
         exec -T mtproxy curl -fsS --max-time 3 http://127.0.0.1:8081/readyz >/dev/null 2>&1; then
      echo ready
      return 0
    fi
    if docker compose -f "${TWPR_ROOT}/docker/docker-compose.yml" \
         --env-file "${TWPR_ROOT}/docker/.env" \
         exec -T mtproxy curl -fsS --max-time 3 http://127.0.0.1:8081/healthz >/dev/null 2>&1; then
      echo alive
      return 0
    fi
  fi
  echo down
  return 1
}

TWPR_cmd_status() {
  TWPR_load_state
  local admin="${TWPR_PORT_ADMIN:-8081}"
  echo ""
  echo -e "  ${C_BOLD}Статус сервисов${C_RESET}  ${C_DIM}(без health-probe)${C_RESET}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"

  if TWPR_is_docker; then
    TWPR_info "Режим: ${C_BOLD}Docker Compose${C_RESET}"
    if [[ -f "${TWPR_ROOT}/docker/.env" ]]; then
      (cd "${TWPR_ROOT}/docker" && docker compose --env-file .env ps) 2>/dev/null || TWPR_warn "docker compose ps недоступен"
    else
      TWPR_warn "Нет ${TWPR_ROOT}/docker/.env — сначала: tgwebproxyr docker setup"
      return 1
    fi
    if [[ -n "${TWPR_HOSTNAME:-}" ]]; then
      echo ""
      TWPR_info "Hostname: ${TWPR_HOSTNAME}"
    fi
    echo ""
    TWPR_info "Проверка healthz/readyz:  ${C_BOLD}tgwebproxyr health${C_RESET}"
    return 0
  fi

  local units=(caddy tproxy-firewall mtproxy tproxy-server)
  local u st
  for u in "${units[@]}"; do
    st="$(TWPR_service_state "$u")"
    case "$st" in
      active)   TWPR_ok "$u — active" ;;
      inactive) TWPR_warn "$u — inactive" ;;
      *)        TWPR_err "$u — не найден" ;;
    esac
  done

  echo ""
  TWPR_info "Порты: HTTP ${TWPR_PORT_HTTP:-80} · HTTPS ${TWPR_PORT_HTTPS:-443} · relay ${TWPR_PORT_RELAY:-8080} · admin ${admin} · mtproxy ${TWPR_PORT_MTPROXY:-2398}"
  if [[ -n "${TWPR_HOSTNAME:-}" ]]; then
    echo ""
    TWPR_info "Hostname: ${TWPR_HOSTNAME}"
  fi
  echo ""
  TWPR_info "Проверка healthz/readyz:  ${C_BOLD}tgwebproxyr health${C_RESET}"
}

TWPR_cmd_health() {
  TWPR_load_state
  local admin="${TWPR_PORT_ADMIN:-8081}" hz
  echo ""
  echo -e "  ${C_BOLD}Проверка работоспособности${C_RESET}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
  TWPR_info "Пробую healthz / readyz…"
  hz="$(TWPR_health_probe 2>/dev/null || echo down)"
  case "$hz" in
    ready) TWPR_ok "relay readyz OK (backend жив)" ;;
    alive) TWPR_warn "relay healthz OK, readyz ещё нет" ;;
    *)     TWPR_err "relay health недоступен — смотрите: tgwebproxyr logs" ;;
  esac

  if [[ -n "${TWPR_HOSTNAME:-}" ]]; then
    echo ""
    TWPR_info "HTTPS ${TWPR_HOSTNAME}…"
    if [[ "${TWPR_PORT_HTTPS:-443}" == "443" ]]; then
      TWPR_info "Сайт: https://${TWPR_HOSTNAME}/"
    else
      TWPR_info "Сайт: https://${TWPR_HOSTNAME}:${TWPR_PORT_HTTPS}/"
    fi
    if curl -fsSk --max-time 5 "https://${TWPR_HOSTNAME}/" -o /dev/null 2>/dev/null; then
      TWPR_ok "HTTPS отвечает"
    else
      TWPR_warn "HTTPS с хоста не открылся (DNS/ACME/firewall?)"
    fi
  fi
}

TWPR_cmd_link() {
  TWPR_load_state
  if TWPR_is_docker; then
    TWPR_docker_ensure_env 2>/dev/null || true
  fi
  if [[ -z "${TWPR_HOSTNAME:-}" || -z "${TWPR_SECRET:-}" ]]; then
    TWPR_err "Прокси ещё не настроен. Запустите: tgwebproxyr setup"
    return 1
  fi
  echo ""
  echo -e "  ${C_BOLD}Ссылки для Telegram Desktop 7.1.1+${C_RESET}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
  echo "  Hostname  ${TWPR_HOSTNAME}"
  echo "  Secret    ${TWPR_SECRET}"
  echo ""
  echo -e "  ${C_BOLD}tg://${C_RESET}"
  echo "  $(TWPR_tg_link)"
  echo ""
  echo -e "  ${C_BOLD}https://t.me${C_RESET}"
  echo "  $(TWPR_web_link)"
  echo ""
  TWPR_info "Settings → Advanced → Connection type → Add proxy → WEB"
  TWPR_info "Hostname без https:// и без порта. Порт всегда 443."
}

TWPR_cmd_metrics() {
  local admin="${TWPR_PORT_ADMIN:-8081}"
  TWPR_load_state
  if ! curl -fsS --max-time 3 "http://127.0.0.1:${admin}/metrics" 2>/dev/null; then
    TWPR_err "Метрики недоступны (нужен работающий tproxy-server)"
    return 1
  fi
}

TWPR_cmd_logs() {
  TWPR_load_state
  if TWPR_is_docker; then
    TWPR_docker_compose logs --tail="${2:-80}" "${1:-}"
    return
  fi
  local unit="${1:-tproxy-server}"
  local lines="${2:-80}"
  journalctl -u "$unit" -u mtproxy -u caddy --no-pager -n "$lines"
}
