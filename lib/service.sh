#!/usr/bin/env bash
# TgWebProxyR — start / stop / restart (Docker или systemd)

TWPR_cmd_start() {
  TWPR_require_root
  TWPR_load_state
  if TWPR_is_docker; then
    TWPR_docker_ensure_env 2>/dev/null || true
    TWPR_docker_compose up -d --remove-orphans
    TWPR_ok "Docker-стек запущен"
  else
    systemctl enable --now tproxy-firewall mtproxy tproxy-server caddy 2>/dev/null || true
    TWPR_ok "Сервисы запущены"
  fi
  TWPR_cmd_status
}

TWPR_cmd_stop() {
  TWPR_require_root
  TWPR_load_state
  if TWPR_is_docker; then
    TWPR_docker_compose stop "$@"
    TWPR_ok "Docker-стек остановлен"
  else
    systemctl stop caddy tproxy-server mtproxy 2>/dev/null || true
    TWPR_ok "Сервисы остановлены"
  fi
}

TWPR_cmd_restart() {
  TWPR_require_root
  TWPR_load_state
  if TWPR_is_docker; then
    TWPR_docker_ensure_env 2>/dev/null || true
    TWPR_docker_compose restart "$@"
    TWPR_ok "Docker-стек перезапущен"
  else
    systemctl restart tproxy-firewall mtproxy tproxy-server caddy 2>/dev/null || true
    TWPR_ok "Сервисы перезапущены"
  fi
  sleep 2
  TWPR_cmd_status
}
