#!/usr/bin/env bash
# TgWebProxyR — uninstall

TWPR_cmd_uninstall() {
  TWPR_require_root
  TWPR_banner
  TWPR_load_state
  TWPR_warn "Остановлю и удалю Caddy / tproxy-server / mtproxy (и Docker-стек, если был)"
  local choice="" keep="" keep_tls=""
  TWPR_ask_yn choice "Точно удалить TgWebProxyR" "n"
  [[ "$choice" == "yes" ]] || return 1

  TWPR_ask_yn keep "Сохранить сайт ${TWPR_SITE_DIR}" "Y"
  TWPR_ask_yn keep_tls "Сохранить TLS-сертификаты (Caddy / LE)" "Y"

  if [[ -f "${TWPR_ROOT}/docker/docker-compose.yml" ]] && command -v docker >/dev/null 2>&1; then
    if [[ "$keep_tls" == "yes" ]]; then
      # без -v: caddy_data остаётся
      (cd "${TWPR_ROOT}/docker" && docker compose --env-file .env down --remove-orphans 2>/dev/null) || true
    else
      (cd "${TWPR_ROOT}/docker" && docker compose --env-file .env down -v 2>/dev/null) || true
    fi
  fi

  systemctl stop caddy tproxy-server mtproxy tproxy-firewall refresh-mtproxy-config.timer tgwebproxyr-bot tgwebproxyr-api tgwebproxyr-autobackup.timer 2>/dev/null || true
  systemctl disable caddy tproxy-server mtproxy tproxy-firewall refresh-mtproxy-config.timer tgwebproxyr-bot tgwebproxyr-api tgwebproxyr-autobackup.timer 2>/dev/null || true

  rm -f /etc/systemd/system/caddy.service \
        /etc/systemd/system/tproxy-server.service \
        /etc/systemd/system/mtproxy.service \
        /etc/systemd/system/tproxy-firewall.service \
        /etc/systemd/system/refresh-mtproxy-config.service \
        /etc/systemd/system/refresh-mtproxy-config.timer \
        /etc/systemd/system/tgwebproxyr-bot.service \
        /etc/systemd/system/tgwebproxyr-api.service \
        /etc/systemd/system/tgwebproxyr-autobackup.service \
        /etc/systemd/system/tgwebproxyr-autobackup.timer
  rm -rf /etc/systemd/system/mtproxy.service.d
  systemctl daemon-reload 2>/dev/null || true

  rm -f /usr/local/bin/tproxy-server /usr/local/bin/tgwebproxyr /usr/local/bin/webproxyl
  rm -rf /opt/tgwebproxyr /opt/webproxyl /etc/tgwebproxyr /etc/webproxyl /etc/tproxy-server /etc/mtproxy
  if [[ "$keep_tls" != "yes" ]]; then
    rm -rf /var/lib/caddy
  else
    TWPR_ok "Сертификаты Caddy оставлены в /var/lib/caddy (и docker volume, если был)"
  fi
  # Let's Encrypt (/etc/letsencrypt) никогда не трогаем — чужой certbot
  rm -f /etc/caddy/Caddyfile /etc/nftables.d/tproxy-backend.nft \
        /etc/profile.d/tgwebproxyr.sh /etc/profile.d/webproxyl.sh 2>/dev/null || true

  if [[ "$keep" != "yes" ]]; then
    rm -rf "$TWPR_SITE_DIR"
  fi

  nft delete table inet tproxy_backend 2>/dev/null || true

  echo ""
  TWPR_ok "Удаление завершено"
  echo -e "  ${C_DIM}Команда tgwebproxyr больше недоступна.${C_RESET}"
  echo ""
  # не возвращаемся в меню — скрипт уже с диска стёрт
  exit 0
}
