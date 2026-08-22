# Установка

## One-liner

```bash
wget -qO /tmp/twpr.sh \
  https://raw.githubusercontent.com/RasmusVraa/TgWebProxyR/main/install.sh \
  && sudo bash /tmp/twpr.sh
```

Не используйте `curl … | bash` — мастеру нужен TTY.

## Что спросит мастер

1. **Режим**: Docker быстро / Docker расширенно / Native быстро / Native расширенно  
2. **Домен** (DNS A на VPS, без CDN на первом ACME)  
3. **Email** для Let's Encrypt  
4. Secret — генерируется сам (в advanced можно задать свой)

Профиль **`default`** сразу попадает в `/etc/tgwebproxyr/profiles.json` и в ссылку `tgwebproxyr link`.

## Флаги `install.sh` / `setup`

| Флаг | Значение |
| --- | --- |
| `--docker` | Compose + образы GHCR |
| `--native` | systemd + upstream install |
| `--quick` | минимум вопросов |
| `--advanced` | порты / workers / secret |
| `--hostname` | домен |
| `--email` | ACME email |
| `--yes` | без подтверждений |

Переменные: `TWPR_HOSTNAME`, `TWPR_EMAIL`, `TWPR_SECRET`, `TWPR_YES=1`.

### Примеры

```bash
# Docker без вопросов
sudo TWPR_HOSTNAME=proxy.example.com \
     TWPR_EMAIL=you@example.com \
     TWPR_YES=1 bash /tmp/twpr.sh --docker --quick

# Native расширенно
sudo bash /tmp/twpr.sh --native --advanced

# Уже установлено — снова мастер
sudo tgwebproxyr setup --docker --quick
```

## После установки

```bash
sudo tgwebproxyr          # меню
sudo tgwebproxyr link     # ссылки default
sudo tgwebproxyr status
sudo tgwebproxyr health   # healthz / readyz / HTTPS
```

Для non-root: алиас в `/etc/profile.d/tgwebproxyr.sh`  
(`tgwebproxyr` → `sudo tgwebproxyr`). Применить: `source /etc/profile.d/tgwebproxyr.sh`.

## Обновление с релиза

```bash
# с v1.6.9 — обновляет и скрипт, и стек:
sudo tgwebproxyr update

# если на сервере ещё старый update (≤1.6.8):
wget -qO /tmp/twpr.sh \
  https://raw.githubusercontent.com/RasmusVraa/TgWebProxyR/main/install.sh \
  && sudo bash /tmp/twpr.sh --update-only
```

После обновления до **1.6.12** (Docker): `sudo tgwebproxyr secret apply` — подтянуть новый relay и mtproxy (`--nat-info`, трафик по пользователям).

Актуальный релиз: [v1.6.12](https://github.com/RasmusVraa/TgWebProxyR/releases/tag/v1.6.12).

## Требования

- Ubuntu 22.04+ / Debian 12+, **x86_64**
- Публичный IPv4, DNS A, порты **80** и **443**
- Root
- Для Docker-режима: Docker Engine + Compose plugin

## Уже есть сертификат (Let's Encrypt и др.)

При setup, если найден fullchain+privkey для домена, мастер спросит:  
**«Подхватить его (не выпускать новый ACME)»** — по умолчанию да.

Ищет:

| Путь |
| --- |
| `/etc/letsencrypt/live/<hostname>/fullchain.pem` + `privkey.pem` |
| `/etc/ssl/tgwebproxyr/<hostname>/…` |
| `/etc/tgwebproxyr/certs/fullchain.pem` + `privkey.pem` |
| env `TWPR_TLS_CERT` + `TWPR_TLS_KEY` |

```bash
sudo tgwebproxyr certs status
sudo tgwebproxyr certs detect
```

Режим пишется в `settings.env` (`TWPR_TLS_MODE=file|acme`).  
`/etc/letsencrypt` uninstall **не трогает**. Caddy-хранилище можно сохранить при удалении.

См. также: [[Docker-vs-Native]], [[Troubleshooting]].
