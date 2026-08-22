# Changelog

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

- Пошаговый мастер установки (8 шагов) прямо из one-liner
- `install.sh` сразу запускает wizard, без отдельных команд
- Дашборд вместо пустого меню: статус, health, ссылки
- Исправлено тихое падение `setup` после баннера

## 1.0.1 — 2026-08-22

- Переименование проекта в **TgWebProxyR**
- CLI-команда: `tgwebproxyr`
- PNG-баннер в README

## 1.0.0 — 2026-08-22

- Первый релиз (ранее WebProxyL)
