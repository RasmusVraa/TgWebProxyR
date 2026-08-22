# TgWebProxyR Wiki

Установщик и CLI для Telegram **WEB**-прокси на базе [`tproxy-server`](https://github.com/telegramdesktop/tproxy-server).

> Скрипт навайбкоден — используйте с осторожностью.  
> Актуальная версия: **[v1.6.12](https://github.com/RasmusVraa/TgWebProxyR/releases/tag/v1.6.12)** · [README](https://github.com/RasmusVraa/TgWebProxyR#readme)

## Страницы

| | |
| --- | --- |
| [[Installation]] | one-liner, флаги, TLS, обновление |
| [[Docker-vs-Native]] | Compose или systemd |
| [[Users]] | несколько secret / профили |
| [[CLI]] | меню и команды |
| [[Bot]] | Telegram-бот |
| [[API]] | Shop REST API |
| [[Backups]] | архивы и автобэкап |
| [[Client]] | подключение Desktop |
| [[Troubleshooting]] | типовые поломки |

## Быстрый старт

```bash
wget -qO /tmp/twpr.sh \
  https://raw.githubusercontent.com/RasmusVraa/TgWebProxyR/main/install.sh \
  && sudo bash /tmp/twpr.sh

sudo tgwebproxyr link
```

В Desktop ≥ 7.1.1: **Settings → Advanced → Connection type → Add proxy → WEB**.

## Что умеет (v1.6.12)

- Docker или Native установка  
- Несколько пользователей на одном домене (`secret add` / бот / API)  
- Трафик **по каждому пользователю** (бот, `metrics`, API)  
- MTProxy сам ставит `--nat-info` за Docker/NAT  
- Подхват уже выпущенного TLS (Let's Encrypt / файлы)  
- `tgwebproxyr update` обновляет и менеджер, и стек  
- Telegram-бот и Shop API на `127.0.0.1:8787`  
- Автобэкап + отправка архива админу  

Репозиторий: https://github.com/RasmusVraa/TgWebProxyR  
Релизы: https://github.com/RasmusVraa/TgWebProxyR/releases
