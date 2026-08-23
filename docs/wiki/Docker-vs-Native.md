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

## Как запустить Docker (рекомендуется)

Не нужно писать `docker-compose.yml` с нуля — он уже в репозитории.

```bash
wget -qO /tmp/twpr.sh \
  https://raw.githubusercontent.com/RasmusVraa/TgWebProxyR/main/install.sh \
  && sudo bash /tmp/twpr.sh --docker --quick
```

После установки:

| Путь | Что это |
| --- | --- |
| `/opt/tgwebproxyr/docker/docker-compose.yml` | готовый Compose |
| `/opt/tgwebproxyr/docker/.env` | hostname, secret, порты, образы |
| `/etc/tgwebproxyr/profiles.json` | пользователи / secrets |
| `/srv/tproxy-site` | публичный сайт |

```bash
sudo tgwebproxyr docker status
sudo tgwebproxyr docker logs
sudo tgwebproxyr link
```

Исходник compose: [docker/docker-compose.yml](https://github.com/RasmusVraa/TgWebProxyR/blob/main/docker/docker-compose.yml).

## Почему Docker делит network namespace

Upstream `tproxy-server` требует **numeric loopback** и для listen, и для backend / admin.  
Поэтому **нельзя** просто повесить три контейнера в одну bridge-сеть с разными IP.

| Сервис | Как сидит в сети |
| --- | --- |
| `mtproxy` | якорь: публичные `:80`/`:443`, внутри `127.0.0.1:2398` |
| `relay` | `network_mode: service:mtproxy` — тот же localhost |
| `caddy` | тоже в netns mtproxy → `reverse_proxy 127.0.0.1:8080` |
| `admin-proxy` | socat: хост `127.0.0.1:8081` → admin relay |

Admin relay слушает только `127.0.0.1:8081` внутри netns. С хоста метрики:  
`127.0.0.1:8081` → `18081` → `127.0.0.1:8081` (≥1.6.11).

MTProxy за Docker обычно нужен `--nat-info` — с **v1.6.12** entrypoint ставит его сам (см. [[Troubleshooting]]).

## Compose volumes (важно)

| Хост | Контейнер |
| --- | --- |
| `/etc/tgwebproxyr/profiles.json` | relay + mtproxy `/run/twpr/profiles.json` |
| `/srv/tproxy-site` | relay `/srv/tproxy-site` |
| `docker/entrypoint-*.sh` | hot-path без полной пересборки образа |

`profiles.json` и сайт должны существовать **до** `compose up` (иначе Docker может создать каталог вместо файла).

## Ручной `docker compose up` (если без мастера)

1. Подготовьте на хосте `profiles.json` и `/srv/tproxy-site`.  
2. Скопируйте каталог `docker/` из репо (или `/opt/tgwebproxyr/docker`).  
3. Заполните `.env` (`TWPR_HOSTNAME`, `TWPR_EMAIL`, `TWPR_SECRET`, …).  
4. `docker compose --env-file .env up -d` из этого каталога.

Проще и надёжнее — `tgwebproxyr setup --docker`.

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
