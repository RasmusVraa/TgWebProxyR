#!/usr/bin/env bash
# TgWebProxyR — uninstall

TWPR_cmd_uninstall() {
  TWPR_require_root
  TWPR_banner
  TWPR_warn "Остановлю и удалю Caddy / tproxy-server / mtproxy"
  local choice="" keep=""
  TWPR_ask_yn choice "Точно удалить TgWebProxyR" "n"
  [[ "$choice" == "yes" ]] || return 0

  TWPR_ask_yn keep "Сохранить сайт ${TWPR_SITE_DIR}" "Y"

  systemctl stop caddy tproxy-server mtproxy tproxy-firewall refresh-mtproxy-config.timer tgwebproxyr-bot 2>/dev/null || true
  systemctl disable caddy tproxy-server mtproxy tproxy-firewall refresh-mtproxy-config.timer tgwebproxyr-bot 2>/dev/null || true

  rm -f /etc/systemd/system/caddy.service \
        /etc/systemd/system/tproxy-server.service \
        /etc/systemd/system/mtproxy.service \
        /etc/systemd/system/tproxy-firewall.service \
        /etc/systemd/system/refresh-mtproxy-config.service \
        /etc/systemd/system/refresh-mtproxy-config.timer \
        /etc/systemd/system/tgwebproxyr-bot.service
  systemctl daemon-reload 2>/dev/null || true

  rm -f /usr/local/bin/tproxy-server /usr/local/bin/tgwebproxyr /usr/local/bin/webproxyl
  rm -rf /opt/tgwebproxyr /opt/webproxyl /etc/tgwebproxyr /etc/webproxyl /etc/tproxy-server /etc/mtproxy /var/lib/caddy
  rm -f /etc/caddy/Caddyfile /etc/nftables.d/tproxy-backend.nft \
        /etc/profile.d/tgwebproxyr.sh /etc/profile.d/webproxyl.sh 2>/dev/null || true

  if [[ "$keep" != "yes" ]]; then
    rm -rf "$TWPR_SITE_DIR"
  fi

  nft delete table inet tproxy_backend 2>/dev/null || true
  TWPR_ok "Удаление завершено"
}
