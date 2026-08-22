# TgWebProxyR

**TgWebProxyR** — однострочный установщик и CLI-менеджер для нового типа прокси Telegram **WEB**.

Под капотом ставится официальный proof-of-concept движок
[`telegramdesktop/tproxy-server`](https://github.com/telegramdesktop/tproxy-server):
публичный HTTPS-сайт + WebView-мост, который мультиплексирует MTProxy-потоки
и отдаёт их локальному официальному MTProxy. Для провайдера это обычный веб-трафик
на ваш домен.

> Нужен **Telegram Desktop 7.1.1+** (тип прокси **WEB** в Connection settings).

<p align="center">
  <img alt="TgWebProxyR" src="docs/banner.svg" width="720">
</p>

---

## Навигация

- [Как это работает](#how)
- [Установка](#install)
- [Быстрый старт](#quickstart)
- [Подключение в Telegram](#client)
- [CLI](#cli)
- [Публичный сайт](#site)
- [Требования](#requirements)
- [Безопасность](#security)
- [Обновление и удаление](#ops)
- [Устранение проблем](#troubleshoot)
- [Благодарности](#thanks)

---

<a id="how"></a>
## Как это работает

```text
Telegram Desktop 7.1.1+
  тип прокси: WEB
  hostname + MTProxy secret
        │
        ▼
  встроенный WebView → HTTPS к вашему домену :443
  мультиплекс OPEN/DATA/WINDOW/CLOSE
        │
        ▼
  Caddy (публичный TLS)
        ├─ обычные страницы сайта
        └─ bridge → tproxy-server (127.0.0.1:8080)
                         │
                         ▼
                   official MTProxy (127.0.0.1:2398)
                         │
                         ▼
                   Telegram DC
```

Клиент вводит только **hostname** и **secret**. Порт всегда **443**, схема всегда
**HTTPS**. Secret в JavaScript не попадает: capability для bridge-страницы
вычисляется локально в приложении.

Ссылки:

```text
tg://webproxy?server=proxy.example.com&secret=<32hex>
https://t.me/webproxy?server=proxy.example.com&secret=<32hex>
```

> Публичный `t.me/webproxy` ещё может не резолвиться в веб-фронте Telegram —
> открывайте ссылку прямо в Desktop или вводите поля вручную.

---

<a id="install"></a>
## Установка

На чистом **Ubuntu 22.04+ / Debian 12+** (x86_64):

```bash
wget -qO /tmp/tgwebproxyr-install.sh \
  https://raw.githubusercontent.com/RasmusVraa/TgWebProxyR/main/install.sh \
  && sudo bash /tmp/tgwebproxyr-install.sh
```

Или:

```bash
curl -fsSL https://raw.githubusercontent.com/RasmusVraa/TgWebProxyR/main/install.sh | sudo bash
```

После загрузки менеджера сразу запускается мастер `tgwebproxyr setup`.

Повторный вход в меню:

```bash
sudo tgwebproxyr
```

Пропустить мастер при bootstrap:

```bash
sudo TWPR_SKIP_SETUP=1 bash /tmp/tgwebproxyr-install.sh
sudo tgwebproxyr setup
```

---

<a id="quickstart"></a>
## Быстрый старт

1. Создайте DNS **A**-запись: `proxy.example.com → IP_VPS` (без CDN).
2. Откройте на хостинге/firewall **TCP 80 и 443** (SSH по возможности ограничьте своим IP).
3. Запустите установку одной командой выше.
4. В мастере укажите:
   - домен
   - email для Let’s Encrypt
   - secret (можно сгенерировать автоматически)
5. Получите ссылку:

```bash
sudo tgwebproxyr link
```

6. В Telegram Desktop: **Settings → Advanced → Connection type → Add proxy → WEB**.

---

<a id="client"></a>
## Подключение в Telegram

| Поле | Значение |
|------|----------|
| Тип | **WEB** |
| Hostname | `proxy.example.com` (без `https://`, без порта, без `/`) |
| Secret | 32 hex-символа (опционально с префиксом `dd`) |

Порт и TLS фиксированы протоколом: всегда **443 / HTTPS**.

Текущая поддержка клиентов (по документации upstream):

- **Telegram Desktop** — реализовано (native WebView + fallback)
- **Android** — experimental PoC в репозитории tproxy-server
- **iOS** — в планах upstream

---

<a id="cli"></a>
## CLI

```text
tgwebproxyr                 интерактивное меню
tgwebproxyr setup           мастер установки
tgwebproxyr status          caddy / mtproxy / tproxy-server / healthz
tgwebproxyr link            tg:// и https://t.me/webproxy
tgwebproxyr logs [unit]     journalctl
tgwebproxyr metrics         http://127.0.0.1:8081/metrics
tgwebproxyr update          deploy/update-relay.sh
tgwebproxyr reinstall       повторный официальный install
tgwebproxyr secret show
tgwebproxyr secret rotate
tgwebproxyr secret add      ещё один профиль на том же hostname
tgwebproxyr uninstall
```

Состояние менеджера: `/etc/tgwebproxyr/settings.env`  
Движок: `/opt/tgwebproxyr/engine/tproxy-server`  
Сайт: `/srv/tproxy-site`

---

<a id="site"></a>
## Публичный сайт

Upstream **намеренно не кладёт** общий starter-сайт: одинаковые шаблоны легко
узнаются активным зондированием. TgWebProxyR кладёт **свой** стартовый пакет
«Northwind Field Notes» в `/srv/tproxy-site` только если каталога ещё нет.

Обязательно замените тексты, структуру и визуал на свои. Контракт сайта —
см. [`PUBLIC_SITE.md`](https://github.com/telegramdesktop/tproxy-server/blob/master/PUBLIC_SITE.md):

- нужен `index.html`
- CSS/JS только внешние, same-origin
- без inline `<style>` / `<script>`, форм, analytics, frames

После правок:

```bash
sudo /usr/local/bin/tproxy-server \
  -config /etc/tproxy-server/config.json \
  -profiles-file /etc/tproxy-server/profiles.json \
  -check
sudo systemctl restart tproxy-server
```

---

<a id="requirements"></a>
## Требования

| | |
|--|--|
| ОС | Ubuntu 22.04+ / Debian 12+ |
| CPU | **x86_64** (ограничение stock MTProxy) |
| Сеть | публичный IPv4, DNS A на хост, без CDN на первом деплое |
| Порты | 80, 443 снаружи; 2398 / 8080 / 8081 / 8888 — только localhost |
| Права | root / passwordless sudo |
| Клиент | Telegram Desktop **≥ 7.1.1** |

Установщик upstream ставит Caddy, nftables-защиту backend-портов, Go-релей,
дотпиненный билд официального MTProxy и systemd-юниты.

---

<a id="security"></a>
## Безопасность

- Снаружи слушает только Caddy (80/443).
- Relay, admin (`8081`), MTProxy client-port (`2398`) и stats (`8888`) — loopback.
- nftables-таблица `tproxy_backend` режет внешний доступ к backend-портам.
- Profiles-файл с secret — режим `0400`.
- Не логируйте bridge-URL и Authorization-заголовки.
- Не ставьте CDN/прокси перед первым деплоем — сломаете ACME и Host/IP trust.

---

<a id="ops"></a>
## Обновление и удаление

Обновить только Go-релей (конфиги/сайт/Caddy не трогает):

```bash
sudo tgwebproxyr update
```

Полный повтор официального install (осторожно: перезапишет Caddyfile и single-profile):

```bash
sudo tgwebproxyr reinstall
```

Удаление:

```bash
sudo tgwebproxyr uninstall
```

---

<a id="troubleshoot"></a>
## Устранение проблем

| Симптом | Что проверить |
|---------|----------------|
| Caddy не выдал сертификат | A/AAAA на этот хост, 80/443 открыты, нет CDN; битый AAAA лучше удалить |
| `/readyz` = 503 | `systemctl status mtproxy`, доступность `127.0.0.1:2398` |
| WebView показывает сайт, а не bridge | hostname+secret должны **точно** совпадать с профилем |
| Клиент «Connecting…» | Desktop ≥ 7.1.1, WebView может открыть `https://hostname`, смотрите `tgwebproxyr logs` |
| Архитектура не x86_64 | stock MTProxy так не соберётся — нужен amd64 VPS |

Диагностика без секретов:

```bash
sudo tgwebproxyr status
sudo tgwebproxyr logs
curl -fsS http://127.0.0.1:8081/healthz
curl -fsS http://127.0.0.1:8081/readyz
```

---

<a id="thanks"></a>
## Благодарности

- [telegramdesktop/tproxy-server](https://github.com/telegramdesktop/tproxy-server) — протокол и reference-сервер WEB proxy
- [TelegramMessenger/MTProxy](https://github.com/TelegramMessenger/MTProxy) — backend
- Идея удобного server-side менеджера вдохновлена экосистемой вроде [MTProxyL](https://github.com/Liafanx/MTProxyL), но TgWebProxyR — отдельный проект под новый тип **WEB**, без копирования кода

## Лицензия

MIT — см. [LICENSE](LICENSE).  
Код движка `tproxy-server` распространяется на условиях своего репозитория.
