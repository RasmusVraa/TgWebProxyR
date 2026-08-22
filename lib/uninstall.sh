#!/usr/bin/env bash
# WebProxyL — uninstall

wpl_cmd_uninstall() {
  wpl_require_root
  wpl_banner
  wpl_warn "Будут остановлены и удалены сервисы WEB-прокси (Caddy/tproxy/mtproxy)."
  wpl_warn "Каталог сайта ${WPL_SITE_DIR} можно сохранить."
  wpl_confirm "Удалить WebProxyL и движок" "n" || return 0

  local keep_site=1
  wpl_confirm "Сохранить публичный сайт ${WPL_SITE_DIR}" "Y" || keep_site=0

  systemctl stop caddy tproxy-server mtproxy tproxy-firewall refresh-mtproxy-config.timer 2>/dev/null || true
  systemctl disable caddy tproxy-server mtproxy tproxy-firewall refresh-mtproxy-config.timer 2>/dev/null || true

  rm -f /etc/systemd/system/caddy.service \
        /etc/systemd/system/tproxy-server.service \
        /etc/systemd/system/mtproxy.service \
        /etc/systemd/system/tproxy-firewall.service \
        /etc/systemd/system/refresh-mtproxy-config.service \
        /etc/systemd/system/refresh-mtproxy-config.timer
  systemctl daemon-reload

  rm -f /usr/local/bin/tproxy-server /usr/local/bin/webproxyl
  rm -rf /opt/webproxyl /etc/webproxyl /etc/tproxy-server /etc/mtproxy /var/lib/caddy
  rm -f /etc/caddy/Caddyfile /etc/nftables.d/tproxy-backend.nft 2>/dev/null || true

  if [[ "$keep_site" -eq 0 ]]; then
    rm -rf "$WPL_SITE_DIR"
  fi

  # drop nft table if present
  nft delete table inet tproxy_backend 2>/dev/null || true

  wpl_ok "Удаление завершено"
}
