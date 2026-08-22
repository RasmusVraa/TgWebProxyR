# Changelog

## 1.6.11 — 2026-08-22

- Фикс: relay unhealthy — `admin_listen` снова только loopback (tproxy-server так требует)
- Docker: `admin-proxy` (socat) пробрасывает host `127.0.0.1:8081` → admin внутри netns
- `tgwebproxyr metrics` — fallback через `docker compose exec`

## 1.6.10 — 2026-08-22

- Docker: admin relay слушает `0.0.0.0:8081` внутри netns — метрики/health с хоста (`127.0.0.1:8081`) снова работают
- Бот «Трафик»: парсит `tproxy_*` метрики; fallback через `docker compose exec`

## 1.6.9 — 2026-08-22

- `tgwebproxyr update` теперь **сначала обновляет сам менеджер** с GitHub, затем стек
- `install.sh --update-only` — подтянуть `/opt/tgwebproxyr` без мастера setup
- После self-update подтягиваются бот/API, если установлены

## 1.6.8 — 2026-08-22

- TLS: если на сервере уже есть сертификат (Let's Encrypt / файлы) — подхватывается, новый ACME не выпускается
- `tgwebproxyr certs status|detect`
- Uninstall по умолчанию предлагает сохранить TLS (Caddy data / docker volume)

## 1.6.7 — 2026-08-22

- Фикс: новые пользователи — MTProxy получает **все** secrets через несколько `-S` (не только default)
- `secret apply` пересоздаёт весь Docker-стек (mtproxy + relay), не только relay
- Native: drop-in wrapper `twpr-mtproxy.sh` с мульти-secret

## 1.6.6 — 2026-08-22

- Фикс: новые пользователи в Docker снова работают (profiles.json монтируется в relay)
- Имена пользователей: `secret add/rename`, бот спрашивает имя
- Трафик: `tgwebproxyr metrics` и экран в боте из relay `/metrics`
- Shop API: `tgwebproxyr api setup` — REST для магазинов (Bearer token)

## 1.6.5 — 2026-08-22

- Автобэкап: hourly / daily / monthly / off (systemd timer)
- При создании бэкап-файл отправляется админу в Telegram
- В боте: настройка автобэкапа + восстановление из архива

## 1.6.4 — 2026-08-22

- Бот быстрее (без «Доступности» и health-probe в статусе)
- Меню как в ProxyL: страницы пользователей/ссылок, логи, управление прокси
- Профиль `default` в реестре `/etc/tgwebproxyr/profiles.json` — везде первый

## 1.6.3 — 2026-08-22

- После `uninstall` сразу выход из CLI (больше не возвращает в пустое меню)

## 1.6.2 — 2026-08-22

- Меню открывается без health-probe (было медленно)
- Отдельный пункт / команда: `tgwebproxyr health` (healthz/readyz/HTTPS)

## 1.6.1 — 2026-08-22

- Фикс bot setup: admin id больше не портится (UI ушёл в stderr)
- Unit `tgwebproxyr-bot.service` всегда пишется при setup (больше не `service missing`)
- `EnvironmentFile=bot.env`, понятнее статус admin/service

## 1.6.0 — 2026-08-22

- CLI в духе ProxyL / MTProxyL: вложенные меню, `start|stop|restart`, secrets, настройки
- Гибкая установка: **Docker** или **Native**, быстро / расширенно
- `install.sh` / `setup`: `--docker|--native|--quick|--advanced|--hostname|--email|--yes`
- Алиас `tgwebproxyr` → `sudo tgwebproxyr` для обычных пользователей
- README и [GitHub Wiki](https://github.com/RasmusVraa/TgWebProxyR/wiki)

## 1.5.1 — 2026-08-22

- Живой прогресс скачивания Docker-образов (полоска + статус по caddy/relay/mtproxy)

## 1.5.0 — 2026-08-22

- Установка **только Docker**
- Бот как в ProxyL: token → ждём `/start` → admin id сам
- Бот быстрее (короткие timeout, сразу answerCallback, docker-status)
- CLI упрощён (короткое меню)

## 1.4.4 — 2026-08-22

- Дашборд понимает Docker (больше не пишет systemd missing/down)
- Автодетект `TWPR_DEPLOY_MODE=docker` по `docker/.env`
- Проброс `127.0.0.1:8081` для health с хоста
- `tgwebproxyr logs/status` работают через compose

## 1.4.3 — 2026-08-22

- Docker: mtproxy/relay/caddy в одном network namespace (tproxy требует loopback)
- Docker: mtproto-proxy собирается в debian bookworm (фикс GLIBC_2.38)

## 1.4.2 — 2026-08-22

- Docker: бинарники в Releases — сборка на VPS = только download
- Параллельный prefetch + fallback без компиляции MTProxy/Go

## 1.4.1 — 2026-08-22

- Docker: готовые образы GHCR + бинарники в GitHub Releases
- Параллельный prefetch ещё во время вопросов мастера
- Fallback-сборка за секунды: скачивает бинарники, без компиляции на VPS
- Telegram proxy-secret/config внутри образа mtproxy
- CI: `.github/workflows/docker.yml`

## 1.4.0 — 2026-08-22

- Упрощённый установщик: выбор режима «быстро / Docker / расширенно»
- Быстрая установка — только домен + email (secret и порты по умолчанию)
- Non-interactive: `TWPR_HOSTNAME` + `TWPR_EMAIL` + `TWPR_YES=1`
- **Docker Compose**: Caddy + tproxy-server + MTProxy (`docker/`, `tgwebproxyr docker setup`)
- CLI: `tgwebproxyr setup --quick|--docker|--advanced`

## 1.3.0 — 2026-08-22

- Telegram-бот с inline-меню (статус, прокси, пользователи, ссылки, трафик, доступность, бэкапы, doctor)
- CLI: `tgwebproxyr bot setup|start|stop|restart|logs`
- CLI: `tgwebproxyr backup create|list|restore`

## 1.2.3 — 2026-08-22

- Фикс mtproxy `203/EXEC`: слишком жёсткий umask ломал права `/opt/MTProxy`
- `tgwebproxyr doctor` чинит chmod/пересборку mtproto-proxy

## 1.2.2 — 2026-08-22

- Восстановление после `tproxy-server did not become ready`
- Longer ready-wait, soft-fail upstream check, снятие MemoryDenyWriteExecute
- Команда `tgwebproxyr doctor`

## 1.2.1 — 2026-08-22

- Обход падения upstream `go test` (flake `TestLoadAcceptsSystemdCredentialReadPermissions` на части VPS)
- Установка продолжает `go build` и деплой

## 1.2.0 — 2026-08-22

- Выбор рабочих портов в мастере (HTTP/HTTPS/relay/admin/mtproxy)
- Патч Caddyfile, config.json, profiles, mtproxy.service, nftables после install
- Предупреждение: Telegram WEB-клиент всегда ждёт HTTPS :443

## 1.1.1 — 2026-08-22

- Ввод мастера читает `/dev/tty` (фикс спама при `curl | bash`)
- Лимит на пустые ответы, понятная ошибка вместо бесконечного цикла

## 1.1.0 — 2026-08-22

- Первый публичный релиз менеджера WEB-прокси
