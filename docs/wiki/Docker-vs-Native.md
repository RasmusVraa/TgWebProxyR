# Docker vs Native

TgWebProxyR умеет держать стек двумя способами — как MTProxyL умеет Docker / бинарник.

| | Docker | Native |
| --- | --- | --- |
| Компоненты | `mtproxy` + `relay` + `caddy` (общий network namespace) | systemd: `caddy`, `tproxy-server`, `mtproxy`, `tproxy-firewall` |
| Образы | `ghcr.io/rasmusvraa/tgwebproxyr-relay` · `…-mtproxy` · `caddy:2.8-alpine` | клон `tproxy-server` + сборка |
| Конфиг | `/opt/tgwebproxyr/docker/.env` + `/etc/tgwebproxyr/settings.env` | `/etc/tproxy-server/*`, `/etc/mtproxy/*` |
| Secret | один shared (`TWPR_SECRET`) | profiles.json, несколько пользователей |
| Скорость на чистом VPS | минуты (pull) | дольше (go build / mtproxy) |
| Нужен Docker | да | нет |

## Когда что выбирать

- **Docker** — обычный VPS, быстрый старт, обновление образов одной командой.
- **Native** — несколько WEB-профилей (`secret add`), отладка systemd, нет желания ставить Docker.

## Смена режима

Переносимых «горячих» переключателей нет: сделайте бэкап и прогоните мастер заново.

```bash
sudo tgwebproxyr backup create
sudo tgwebproxyr setup --native   # или --docker
```

## Почему Docker делит network namespace

Upstream `tproxy-server` требует **numeric loopback** и для listen, и для backend.
Поэтому relay и caddy работают в `network_mode: service:mtproxy` — общий `127.0.0.1`.
