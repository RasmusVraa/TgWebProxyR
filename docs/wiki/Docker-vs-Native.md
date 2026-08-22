# Docker vs Native

TgWebProxyR умеет держать стек двумя способами — как MTProxyL умеет Docker / бинарник.

| | Docker | Native |
| --- | --- | --- |
| Компоненты | `mtproxy` + `relay` + `caddy` (общий network namespace) | systemd: `caddy`, `tproxy-server`, `mtproxy`, `tproxy-firewall` |
| Образы | `ghcr.io/rasmusvraa/tgwebproxyr-relay` · `…-mtproxy` · `caddy:2.8-alpine` | клон `tproxy-server` + сборка |
| Конфиг | `/opt/tgwebproxyr/docker/.env` + `/etc/tgwebproxyr/settings.env` | `/etc/tproxy-server/*`, `/etc/mtproxy/*` |
| Secret | `profiles.json` (несколько пользователей) + `TWPR_SECRET` = default | то же, файл engine |
| Скорость на чистом VPS | минуты (pull) | дольше (go build / mtproxy) |
| Нужен Docker | да | нет |

## Когда что выбирать

- **Docker** — обычный VPS, быстрый старт; несколько пользователей через `secret add` / бот / Shop API.
- **Native** — без Docker, отладка systemd, полный контроль на хосте.

## Смена режима

Переносимых «горячих» переключателей нет: сделайте бэкап и прогоните мастер заново.

```bash
sudo tgwebproxyr backup create
sudo tgwebproxyr setup --native   # или --docker
```

## Почему Docker делит network namespace

Upstream `tproxy-server` требует **numeric loopback** и для listen, и для backend.
Поэтому relay и caddy работают в `network_mode: service:mtproxy` — общий `127.0.0.1`.
