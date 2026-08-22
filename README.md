# TgWebProxyR

> **Этот скрипт навайбкоден — используйте с осторожностью.**

Установщик и CLI для Telegram-прокси типа **WEB**: домен на VPS выглядит как обычный сайт, а Desktop ходит через WebView-мост.

Основа — официальный PoC [`telegramdesktop/tproxy-server`](https://github.com/telegramdesktop/tproxy-server) + MTProxy. Клиент: **Telegram Desktop ≥ 7.1.1**, тип прокси **WEB**.

**Сейчас:** [v1.6.7](https://github.com/RasmusVraa/TgWebProxyR/releases/tag/v1.6.7) · [Wiki](https://github.com/RasmusVraa/TgWebProxyR/wiki) · зеркало [`docs/wiki/`](docs/wiki/)

---

## Содержание

- [Схема](#схема)
- [Установка](#установка)
- [Быстрый старт](#быстрый-старт)
- [Docker или Native](#docker-или-native)
- [Пользователи и ссылки](#пользователи-и-ссылки)
- [Telegram-бот](#telegram-бот)
- [Shop API](#shop-api)
- [CLI](#cli)
- [Бэкапы](#бэкапы)
- [Требования](#требования)
- [Безопасность](#безопасность)
- [Обновление](#обновление)
- [Проблемы](#проблемы)
- [Лицензия](#лицензия)

---

## Схема

```text
Telegram Desktop (WEB)
  hostname + secret (32 hex)
        │
        ▼
  HTTPS :443 → ваш домен
        │
        ▼
  Caddy (TLS + сайт)
        └─ bridge → tproxy-server (relay)
                      └─ MTProxy :2398 → DC Telegram
```

Ссылки вида:

```text
tg://webproxy?server=proxy.example.com&secret=<32hex>
https://t.me/webproxy?server=proxy.example.com&secret=<32hex>
```

Несколько пользователей = несколько **secret** на одном hostname.  
Реестр: `/etc/tgwebproxyr/profiles.json` → в **relay** и во все `-S` у **MTProxy**.

---

## Установка

```bash
wget -qO /tmp/twpr.sh \
  https://raw.githubusercontent.com/RasmusVraa/TgWebProxyR/main/install.sh \
  && sudo bash /tmp/twpr.sh
```

Мастер спросит режим (**Docker** / **Native**), домен и email для Let’s Encrypt. Secret для `default` сгенерируется сам.

### Без вопросов

```bash
# Docker (рекомендуется)
sudo TWPR_HOSTNAME=proxy.example.com \
     TWPR_EMAIL=you@example.com \
     TWPR_YES=1 bash /tmp/twpr.sh --docker --quick

# Native (systemd, без Docker)
sudo TWPR_HOSTNAME=proxy.example.com \
     TWPR_EMAIL=you@example.com \
     TWPR_YES=1 bash /tmp/twpr.sh --native --quick
```

Флаги: `--docker` · `--native` · `--quick` · `--advanced` · `--hostname` · `--email` · `--yes`

После установки:

```bash
sudo tgwebproxyr          # меню
sudo tgwebproxyr link     # ссылка default
```

---

## Быстрый старт

1. DNS **A**: `proxy.example.com → IP` (без Cloudflare/CDN на первом выпуске сертификата).
2. Снаружи открыты **TCP 80 и 443**.
3. Установка → Docker · быстро.
4. `sudo tgwebproxyr link` → в Desktop: **Settings → Advanced → Connection type → Add proxy → WEB**.

| Поле | Значение |
| --- | --- |
| Тип | **WEB** |
| Hostname | домен без `https://` и без порта |
| Secret | 32 hex из `link` / бота |

Порт всегда **443**. Нужен Desktop **≥ 7.1.1**.

---

## Docker или Native

| | Docker *(по умолчанию)* | Native |
| --- | --- | --- |
| Стек | Compose: mtproxy + relay + caddy | systemd upstream |
| Образы | `ghcr.io/rasmusvraa/tgwebproxyr-*` | сборка на хосте |
| Несколько пользователей | да (`secret add` / бот / API) | да |
| Когда | чистый VPS, быстрый старт | без Docker, полный контроль |

Смена режима на уже установленном сервере — бэкап и `tgwebproxyr setup` заново.

Подробнее: [Wiki → Docker vs Native](https://github.com/RasmusVraa/TgWebProxyR/wiki/Docker-vs-Native).

---

## Пользователи и ссылки

Профиль **`default`** — основной secret установки. Остальные — именованные пользователи.

```bash
sudo tgwebproxyr secret list
sudo tgwebproxyr secret add alice          # имя → secret → apply
sudo tgwebproxyr secret link alice
sudo tgwebproxyr secret rename alice bob
sudo tgwebproxyr secret remove bob
sudo tgwebproxyr secret apply              # перечитать реестр в движок
sudo tgwebproxyr metrics                   # сессии / байты (:8081)
```

После `add` / `remove` / `rename` профили сами уходят в relay **и** в MTProxy (несколько `-S`).  
Если новый пользователь не коннектится — `secret apply` и в логах mtproxy строка `mtproxy -S count: N`.

---

## Telegram-бот

```bash
sudo tgwebproxyr bot setup
```

1. Token у [@BotFather](https://t.me/BotFather).  
2. Откройте бота → `/start` — admin id подставится сам.  

В боте: статус, прокси start/stop, пользователи (с именами), ссылки, логи, трафик, бэкапы.

```bash
sudo tgwebproxyr bot update    # обновить код бота
sudo tgwebproxyr bot logs
```

Wiki: [Bot](https://github.com/RasmusVraa/TgWebProxyR/wiki/Bot).

---

## Shop API

REST для магазина / своего скрипта (только `127.0.0.1`, Bearer-token):

```bash
sudo tgwebproxyr api setup
sudo tgwebproxyr api token
```

Примеры:

```bash
TOKEN=$(sudo tgwebproxyr api token)

curl -s -H "Authorization: Bearer $TOKEN" \
  http://127.0.0.1:8787/v1/users

curl -s -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"shop_user1"}' \
  http://127.0.0.1:8787/v1/users
```

Эндпоинты: users CRUD, link, traffic, status.  
Wiki: [API](https://github.com/RasmusVraa/TgWebProxyR/wiki/API).

---

## CLI

Меню в духе [MTProxyL](https://github.com/Liafanx/MTProxyL) + те же команды из shell:

```bash
tgwebproxyr                      # интерактивное меню
tgwebproxyr setup                # мастер
tgwebproxyr start|stop|restart
tgwebproxyr status
tgwebproxyr health               # healthz / readyz / HTTPS
tgwebproxyr link
tgwebproxyr logs [svc] [n]
tgwebproxyr doctor

tgwebproxyr secret list|show|link|rotate|add|rename|remove|apply
tgwebproxyr metrics [--raw]
tgwebproxyr api setup|token|status|logs
tgwebproxyr bot setup|update|status|restart|logs
tgwebproxyr backup create|list|restore|auto
tgwebproxyr docker setup|up|down|pull|logs|status
tgwebproxyr update
tgwebproxyr uninstall
```

| Путь | Назначение |
| --- | --- |
| `/opt/tgwebproxyr` | код менеджера |
| `/etc/tgwebproxyr/settings.env` | hostname, режим, порты |
| `/etc/tgwebproxyr/profiles.json` | пользователи / secrets |
| `/etc/tgwebproxyr/bot.env` | бот |
| `/etc/tgwebproxyr/api.env` | Shop API token |
| `/srv/tproxy-site` | публичный сайт |
| `/opt/tgwebproxyr/docker/` | Compose |
| `/opt/tgwebproxyr/backups/` | архивы |

Полный справочник: [Wiki → CLI](https://github.com/RasmusVraa/TgWebProxyR/wiki/CLI).

---

## Бэкапы

```bash
sudo tgwebproxyr backup create
sudo tgwebproxyr backup list
sudo tgwebproxyr backup restore twpr-….tar.gz
sudo tgwebproxyr backup auto daily     # hourly|daily|monthly|off
```

При создании архив можно слать админу в Telegram (настраивается в боте / `backup auto send`).

---

## Требования

| | |
| --- | --- |
| ОС | Ubuntu 22.04+ / Debian 12+ |
| CPU | **x86_64** |
| Сеть | публичный IPv4, DNS A |
| Порты | 80, 443 снаружи |
| Права | root |
| Клиент | Telegram Desktop **≥ 7.1.1** |
| Docker-режим | Docker Engine + Compose plugin |

---

## Безопасность

- Снаружи только **80/443** (Caddy).
- Relay, admin `:8081` и MTProxy — на loopback (в Docker — общий network namespace).
- Shop API слушает **127.0.0.1:8787** — наружу только через свой reverse proxy, если нужно.
- `profiles.json` / `.env` / `api.env` — права `0600` / `0400`.
- Не вешайте CDN до первого успешного ACME.

Публичный сайт — стартовый шаблон; замените тексты  
([PUBLIC_SITE.md](https://github.com/telegramdesktop/tproxy-server/blob/master/PUBLIC_SITE.md)).

### Уже есть сертификат

При установке, если найдены файлы для вашего домена, мастер предложит **подхватить их** (без нового ACME):

- `/etc/letsencrypt/live/<домен>/fullchain.pem` + `privkey.pem`
- `/etc/ssl/tgwebproxyr/<домен>/…`
- `/etc/tgwebproxyr/certs/…`
- или `TWPR_TLS_CERT` / `TWPR_TLS_KEY`

```bash
sudo tgwebproxyr certs status
sudo tgwebproxyr certs detect   # найти и применить
```

Хранилище Caddy (`caddy_data` / `/var/lib/caddy`) при переустановке не сбрасывается, если не удалять volumes.

---

## Обновление

```bash
sudo tgwebproxyr update
# или вручную с релиза:
sudo wget -qO /tmp/twpr.tgz \
  https://github.com/RasmusVraa/TgWebProxyR/archive/refs/tags/v1.6.7.tar.gz
sudo tar -xzf /tmp/twpr.tgz -C /opt/tgwebproxyr --strip-components=1
sudo tgwebproxyr secret apply
sudo tgwebproxyr bot update
```

Удаление: `sudo tgwebproxyr uninstall`.

---

## Проблемы

| Симптом | Что сделать |
| --- | --- |
| Нет сертификата | A/AAAA, 80/443 открыты, нет CDN |
| health / metrics down | `tgwebproxyr health` · `logs` · `doctor` |
| Connecting… / web transport | Desktop ≥ 7.1.1, hostname+secret, HTTPS сайта |
| Новый пользователь не работает | `secret apply`; в логах mtproxy ` -S count: N` |
| Не x86_64 | нужен amd64 VPS |

Подробнее: [Troubleshooting](https://github.com/RasmusVraa/TgWebProxyR/wiki/Troubleshooting).

---

## Благодарности

- [telegramdesktop/tproxy-server](https://github.com/telegramdesktop/tproxy-server)
- [TelegramMessenger/MTProxy](https://github.com/TelegramMessenger/MTProxy)
- UX CLI вдохновлён [MTProxyL](https://github.com/Liafanx/MTProxyL) — это отдельный проект под тип **WEB**

## Лицензия

MIT — [LICENSE](LICENSE).
