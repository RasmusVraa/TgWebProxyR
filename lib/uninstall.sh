#!/usr/bin/env bash
# TgWebProxyR — uninstall

TWPR_cmd_uninstall() {
  TWPR_require_root
  TWPR_banner
  TWPR_warn "Будут остановлены и удалены сервисы WEB-прокси (Caddy/tproxy/mtproxy)."
  TWPR_warn "Каталог сайта ${TWPR_SITE_DIR} можно сохранить."
  TWPR_confirm "Удалить TgWebProxyR и движок" "n" || return 0

  local keep_site=1
  TWPR_confirm "Сохранить публичный сайт ${TWPR_SITE_DIR}" "Y" || keep_site=0

  systemctl stop caddy tproxy-server mtproxy tproxy-firewall refresh-mtproxy-config.timer 2>/dev/null || true
  systemctl disable caddy tproxy-server mtproxy tproxy-firewall refresh-mtproxy-config.timer 2>/dev/null || true

  rm -f /etc/systemd/system/caddy.service \
        /etc/systemd/system/tproxy-server.service \
        /etc/systemd/system/mtproxy.service \
        /etc/systemd/system/tproxy-firewall.service \
        /etc/systemd/system/refresh-mtproxy-config.service \
        /etc/systemd/system/refresh-mtproxy-config.timer
  systemctl daemon-reload

  rm -f /usr/local/bin/tproxy-server /usr/local/bin/tgwebproxyr /usr/local/bin/webproxyl
  rm -rf /opt/tgwebproxyr /opt/webproxyl /etc/tgwebproxyr /etc/webproxyl /etc/tproxy-server /etc/mtproxy /var/lib/caddy
  rm -f /etc/caddy/Caddyfile /etc/nftables.d/tproxy-backend.nft /etc/profile.d/tgwebproxyr.sh /etc/profile.d/webproxyl.sh 2>/dev/null || true

  if [[ "$keep_site" -eq 0 ]]; then
    rm -rf "$TWPR_SITE_DIR"
  fi

  # drop nft table if present
  nft delete table inet tproxy_backend 2>/dev/null || true

  TWPR_ok "Удаление завершено"
}
