# Docker vs Native

Два способа держать стек — как у MTProxyL Docker / бинарник.

| | Docker | Native |
| --- | --- | --- |
| Компоненты | `mtproxy` + `relay` + `caddy` (общий network namespace) | systemd: `caddy`, `tproxy-server`, `mtproxy`, `tproxy-firewall` |
| Образы | `ghcr.io/rasmusvraa/tgwebproxyr-relay` · `…-mtproxy` · `caddy` | клон `tproxy-server` + сборка |
| Конфиг | `/opt/tgwebproxyr/docker/.env` + `/etc/tgwebproxyr/settings.env` | `/etc/tproxy-server/*`, `/etc/mtproxy/*` |
| Пользователи | `profiles.json` → relay **и** все `-S` у mtproxy | то же + wrapper `twpr-mtproxy.sh` |
| Скорость | минуты (pull) | дольше (go build) |
| Нужен Docker | да | нет |

## Когда что

- **Docker** — обычный VPS, быстрый старт, обновление образов.  
- **Native** — без Docker, отладка systemd, полный контроль.

Несколько пользователей работают **в обоих** режимах: [[Users]].

## Смена режима

Горячего переключателя нет: бэкап и мастер заново.

```bash
sudo tgwebproxyr backup create
sudo tgwebproxyr setup --native   # или --docker
```

## Почему Docker делит network namespace

Upstream `tproxy-server` требует **numeric loopback** и для listen, и для backend / admin.  
Relay и caddy: `network_mode: service:mtproxy` — общий `127.0.0.1`.  

Admin relay слушает только `127.0.0.1:8081` внутри netns. С хоста метрики идут через **admin-proxy** (socat):  
`host 127.0.0.1:8081` → `18081` → `127.0.0.1:8081` в контейнере (≥1.6.11).

MTProxy за Docker обычно нужен `--nat-info` — с **v1.6.12** entrypoint ставит его сам (см. [[Troubleshooting]]).

## Compose volumes (важно)

| Хост | Контейнер |
| --- | --- |
| `/etc/tgwebproxyr/profiles.json` | relay + mtproxy `/run/twpr/profiles.json` |
| `docker/entrypoint-*.sh` | hot-path без полной пересборки образа |

Файл `profiles.json` должен существовать **до** `compose up` (иначе Docker создаст каталог).
