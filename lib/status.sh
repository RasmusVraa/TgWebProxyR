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
    local https_url="https://${TWPR_HOSTNAME}/"
    if [[ "${TWPR_PORT_HTTPS:-443}" != "443" ]]; then
      https_url="https://${TWPR_HOSTNAME}:${TWPR_PORT_HTTPS}/"
    fi
    TWPR_info "Сайт: ${https_url}"
    if curl -fsSk --max-time 5 "$https_url" -o /dev/null 2>/dev/null; then
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
  TWPR_ensure_default_profile 2>/dev/null || true
  echo ""
  echo -e "  ${C_BOLD}Профиль  default${C_RESET}  ${C_DIM}(основной)${C_RESET}"
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

TWPR_human_bytes() {
  local b="${1:-0}"
  if command -v numfmt >/dev/null 2>&1; then
    numfmt --to=iec-i --suffix=B "$b" 2>/dev/null && return 0
  fi
  awk -v b="$b" 'BEGIN{
    split("B KiB MiB GiB TiB",u," ");
    for(i=1;b>=1024 && i<5;i++) b/=1024;
    printf "%.1f %s\n", b, u[i]
  }'
}

TWPR_cmd_metrics() {
  local admin="${TWPR_PORT_ADMIN:-8081}" raw="${1:-}"
  TWPR_load_state
  local body=""
  body="$(curl -fsS --max-time 3 "http://127.0.0.1:${admin}/metrics" 2>/dev/null)" || body=""
  if [[ -z "$body" ]] && TWPR_is_docker 2>/dev/null; then
    body="$(TWPR_docker_compose exec -T mtproxy \
      curl -fsS --max-time 3 http://127.0.0.1:8081/metrics 2>/dev/null)" || body=""
    [[ -z "$body" ]] && body="$(TWPR_docker_compose exec -T relay \
      curl -fsS --max-time 3 http://127.0.0.1:8081/metrics 2>/dev/null)" || body=""
  fi
  if [[ -z "$body" ]]; then
    TWPR_err "Метрики недоступны (нужен работающий tproxy-server на :${admin})"
    return 1
  fi
  if [[ "$raw" == "--raw" || "$raw" == "raw" ]]; then
    printf '%s\n' "$body"
    return 0
  fi

  echo ""
  echo -e "  ${C_BOLD}Трафик / сессии${C_RESET}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"

  local sessions="" bytes_in="" bytes_out=""
  # глобальные (без label {profile=…})
  sessions="$(printf '%s\n' "$body" | awk '
    /^[^#]/ && $1 == "tproxy_sessions_live" { print $NF; exit }
  ')"
  bytes_in="$(printf '%s\n' "$body" | awk '
    /^[^#]/ && $1 == "tproxy_bytes_down_total" { print $NF; exit }
  ')"
  bytes_out="$(printf '%s\n' "$body" | awk '
    /^[^#]/ && $1 == "tproxy_bytes_up_total" { print $NF; exit }
  ')"

  if [[ -n "$sessions" ]]; then
    TWPR_ok "активные сессии  ${sessions}"
  else
    TWPR_info "сессии            — (нет метки в /metrics)"
  fi
  if [[ -n "$bytes_out" ]]; then
    TWPR_ok "всего ↑           $(TWPR_human_bytes "${bytes_out%.*}")"
  fi
  if [[ -n "$bytes_in" ]]; then
    TWPR_ok "всего ↓           $(TWPR_human_bytes "${bytes_in%.*}")"
  fi

  if [[ -f "${TWPR_STATE_DIR}/profiles.json" ]] && command -v jq >/dev/null 2>&1; then
    TWPR_info "профилей          $(jq '.profiles|length' "${TWPR_STATE_DIR}/profiles.json" 2>/dev/null || echo '?')"
  fi

  echo ""
  echo -e "  ${C_BOLD}По пользователям${C_RESET}"
  echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
  local per_lines
  per_lines="$(printf '%s\n' "$body" | awk '
    /^[^#]/ && index($1, "{profile=") {
      split($1, a, "profile=\"")
      if (length(a) < 2) next
      split(a[2], b, "\"")
      name = b[1]
      if (name == "") next
      if (index($1, "tproxy_sessions_live{") == 1) sess[name] = $NF
      else if (index($1, "tproxy_bytes_up_total{") == 1) up[name] = $NF
      else if (index($1, "tproxy_bytes_down_total{") == 1) down[name] = $NF
      if (!(name in order)) { order[name] = ++n; names[n] = name }
    }
    END {
      if (n == 0) exit
      for (i = 1; i <= n; i++) {
        p = names[i]
        printf "%s\t%s\t%s\t%s\n", p, sess[p]+0, up[p]+0, down[p]+0
      }
    }
  ')"
  if [[ -z "${per_lines}" ]]; then
    TWPR_info "нет per-profile метрик (нужен relay ≥1.6.12)"
  else
    while IFS=$'\t' read -r pname psess pup pdown; do
      [[ -z "$pname" ]] && continue
      TWPR_ok "$(printf '%-16s sess=%-4s ↑ %-10s ↓ %s' \
        "$pname" "$psess" \
        "$(TWPR_human_bytes "${pup%.*}")" \
        "$(TWPR_human_bytes "${pdown%.*}")")"
    done <<< "$per_lines"
  fi

  echo ""
  TWPR_info "Сырой экспорт: tgwebproxyr metrics --raw"
}

TWPR_cmd_logs() {
  TWPR_load_state
  if TWPR_is_docker; then
    local svc="${1:-}" lines="${2:-80}"
    if [[ -n "$svc" ]]; then
      TWPR_docker_compose logs --tail="$lines" "$svc"
    else
      TWPR_docker_compose logs --tail="$lines"
    fi
    return
  fi
  local unit="${1:-tproxy-server}"
  local lines="${2:-80}"
  journalctl -u "$unit" -u mtproxy -u caddy --no-pager -n "$lines"
}
