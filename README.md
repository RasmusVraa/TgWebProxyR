# TgWebProxyR

## Этот скрипт навайбкоден, используйте с осторожностью!

**TgWebProxyR** — установщик и CLI-менеджер для нового типа прокси Telegram **WEB**.

Под капотом — официальный PoC [`telegramdesktop/tproxy-server`](https://github.com/telegramdesktop/tproxy-server):
публичный HTTPS-сайт + WebView-мост к локальному MTProxy. Для провайдера это
обычный веб-трафик на ваш домен.

> Нужен **Telegram Desktop 7.1.1+** (тип прокси **WEB**).

📖 **Документация:** [GitHub Wiki](https://github.com/RasmusVraa/TgWebProxyR/wiki) · зеркало в репо [`docs/wiki/`](docs/wiki/)


---

## Навигация

- [Как это работает](#how)
- [Установка](#install)
- [Режимы: Docker / Native](#modes)
- [Быстрый старт](#quickstart)
- [Подключение в Telegram](#client)
- [CLI](#cli)
- [Telegram-бот](#bot)
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
  WebView → HTTPS к вашему домену :443
        │
        ▼
  Caddy (TLS)
        ├─ публичный сайт
        └─ bridge → tproxy-server → MTProxy → Telegram DC
```

Ссылки:

```text
tg://webproxy?server=proxy.example.com&secret=<32hex>
https://t.me/webproxy?server=proxy.example.com&secret=<32hex>
```

---

<a id="install"></a>

## Установка

```bash
wget -qO /tmp/twpr.sh \
  https://raw.githubusercontent.com/RasmusVraa/TgWebProxyR/main/install.sh \
  && sudo bash /tmp/twpr.sh
```

Мастер спросит **режим** (Docker / Native) и домен + email. Secret сгенерируется сам.

### Без вопросов

```bash
# Docker, быстро
sudo TWPR_HOSTNAME=proxy.example.com \
     TWPR_EMAIL=you@example.com \
     TWPR_YES=1 bash /tmp/twpr.sh --docker --quick

# Native (systemd + upstream)
sudo TWPR_HOSTNAME=proxy.example.com \
     TWPR_EMAIL=you@example.com \
     TWPR_YES=1 bash /tmp/twpr.sh --native --quick
```

Флаги: `--docker` · `--native` · `--quick` · `--advanced` · `--yes`

После установки:

```bash
sudo tgwebproxyr          # меню
# или (если зашли не под root и сделали source ~/.bashrc):
tgwebproxyr
```

---

<a id="modes"></a>

## Режимы: Docker / Native

| | **Docker** *(по умолчанию)* | **Native** |
| --- | --- | --- |
| Что ставится | Caddy + relay + mtproxy в Compose | systemd-юниты upstream `tproxy-server` |
| Образы | GHCR `ghcr.io/rasmusvraa/tgwebproxyr-*` | сборка/деплой на хосте |
| Логи | `tgwebproxyr logs` / `docker compose logs` | `journalctl` |
| Несколько профилей | `secret add` / profiles.json / бот / Shop API | то же |
| Когда выбирать | быстрый старт, чистый VPS | полный контроль, без Docker |

Сменить носитель на уже установленном сервере — переустановка через меню
**«Установка / переустановка»** или `tgwebproxyr setup`.

---

<a id="quickstart"></a>

## Быстрый старт

1. DNS **A**: `proxy.example.com → IP_VPS` (без CDN).
2. Откройте **TCP 80 и 443**.
3. Установка (см. выше) → Docker · быстро.
4. Ссылка: `sudo tgwebproxyr link`
5. Telegram Desktop → **Settings → Advanced → Connection type → Add proxy → WEB**.

---

<a id="client"></a>

## Подключение в Telegram

| Поле | Значение |
| --- | --- |
| Тип | **WEB** |
| Hostname | `proxy.example.com` (без `https://`, без порта) |
| Secret | 32 hex |

Порт и TLS фиксированы: всегда **443 / HTTPS**. Нужен Desktop **≥ 7.1.1**.

---

<a id="cli"></a>

## CLI

Интерфейс в духе [MTProxyL](https://github.com/Liafanx/MTProxyL): меню + те же действия из командной строки.

```bash
tgwebproxyr                 # меню
tgwebproxyr setup           # мастер
tgwebproxyr start|stop|restart
tgwebproxyr status
tgwebproxyr link
tgwebproxyr logs
tgwebproxyr doctor

tgwebproxyr secret list|show|link|rotate|add|rename|remove|apply
tgwebproxyr metrics
tgwebproxyr api setup|token|status
tgwebproxyr bot setup|update|menu
tgwebproxyr backup create|list|restore|auto
tgwebproxyr docker setup|up|down|pull|logs
tgwebproxyr update
tgwebproxyr uninstall
```

### Установка с аргументами

```bash
tgwebproxyr setup --docker --quick
tgwebproxyr setup --native --advanced \
  --hostname proxy.example.com --email you@ex.com --yes
```

Полный справочник — в [Wiki → CLI](https://github.com/RasmusVraa/TgWebProxyR/wiki/CLI).

Состояние: `/etc/tgwebproxyr/settings.env`  
Сайт: `/srv/tproxy-site`  
Docker: `/opt/tgwebproxyr/docker/`

---

<a id="bot"></a>

## Telegram-бот

```bash
sudo tgwebproxyr bot setup
```

Только **token** → откройте бота → `/start` — admin id подхватится сам.

---

<a id="requirements"></a>

## Требования

| | |
| --- | --- |
| ОС | Ubuntu 22.04+ / Debian 12+ |
| CPU | **x86_64** |
| Сеть | публичный IPv4, DNS A, без CDN на первом деплое |
| Порты | 80, 443 снаружи |
| Права | root |
| Клиент | Telegram Desktop **≥ 7.1.1** |

---

<a id="security"></a>

## Безопасность

- Снаружи только 80/443 (Caddy).
- Relay / admin / MTProxy — loopback (в Docker — общий network namespace).
- Profiles / `.env` с secret — режим `0600`/`0400`.
- Не ставьте CDN перед первым ACME.

Публичный сайт — стартовый шаблон «Northwind»; замените тексты на свои
([PUBLIC_SITE.md](https://github.com/telegramdesktop/tproxy-server/blob/master/PUBLIC_SITE.md)).

---

<a id="ops"></a>

## Обновление и удаление

```bash
sudo tgwebproxyr update      # образы / native engine
sudo tgwebproxyr uninstall
```

---

<a id="troubleshoot"></a>

## Устранение проблем

| Симптом | Что проверить |
| --- | --- |
| Нет сертификата | A/AAAA, 80/443, нет CDN |
| health down | `tgwebproxyr status` · `tgwebproxyr logs` · `tgwebproxyr doctor` |
| Connecting… | Desktop ≥ 7.1.1, hostname+secret совпадают |
| Не x86_64 | нужен amd64 VPS |

Подробнее: [Wiki → Troubleshooting](https://github.com/RasmusVraa/TgWebProxyR/wiki/Troubleshooting).

---

<a id="thanks"></a>

## Благодарности

- [telegramdesktop/tproxy-server](https://github.com/telegramdesktop/tproxy-server)
- [TelegramMessenger/MTProxy](https://github.com/TelegramMessenger/MTProxy)
- UX CLI вдохновлён [MTProxyL](https://github.com/Liafanx/MTProxyL) — отдельный проект под тип **WEB**

## Лицензия

MIT — [LICENSE](LICENSE).
