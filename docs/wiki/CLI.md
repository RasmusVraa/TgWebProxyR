# CLI

Команда: `tgwebproxyr` (от non-root — через sudo / алиас).

## Меню

```bash
tgwebproxyr
# или
tgwebproxyr menu
```

Типичные пункты: ссылки, статус, управление, логи, пользователи, настройки, бот, бэкапы, установка, удаление.

## Прокси

```bash
tgwebproxyr start|stop|restart
tgwebproxyr status
tgwebproxyr health            # healthz / readyz / HTTPS (отдельно от меню)
tgwebproxyr link
tgwebproxyr logs              # compose или journalctl
tgwebproxyr logs relay 200
tgwebproxyr doctor
tgwebproxyr metrics            # всего + по пользователям (≥1.6.12)
tgwebproxyr metrics --raw
tgwebproxyr certs status|detect
```

## Установка

```bash
tgwebproxyr setup
tgwebproxyr setup --docker --quick
tgwebproxyr setup --native --advanced --hostname proxy.example.com --email a@b.c --yes
tgwebproxyr install …         # синоним setup
tgwebproxyr reinstall
```

## Secrets / пользователи

```bash
tgwebproxyr secret list
tgwebproxyr secret show
tgwebproxyr secret link [name]
tgwebproxyr secret rotate [name]
tgwebproxyr secret add [name]
tgwebproxyr secret rename <old> <new>
tgwebproxyr secret remove <name>
tgwebproxyr secret apply      # relay + все -S у mtproxy
```

Подробнее: [[Users]].

## Бот / API / бэкапы / Docker

```bash
tgwebproxyr bot setup|update|status|start|stop|restart|logs|menu
tgwebproxyr api setup|token|status|start|stop|restart|logs|rotate
tgwebproxyr backup create|list|restore <name>
tgwebproxyr backup auto hourly|daily|monthly|off
tgwebproxyr backup auto send on|off
tgwebproxyr docker setup|up|down|restart|status|logs|pull|build
tgwebproxyr update
tgwebproxyr uninstall
tgwebproxyr version
tgwebproxyr help
```

## Пути

| Путь | Назначение |
| --- | --- |
| `/opt/tgwebproxyr` | код менеджера |
| `/etc/tgwebproxyr/settings.env` | hostname, режим, порты |
| `/etc/tgwebproxyr/profiles.json` | пользователи / secrets |
| `/etc/tgwebproxyr/bot.env` | бот |
| `/etc/tgwebproxyr/api.env` | Shop API token |
| `/etc/tgwebproxyr/autobackup.env` | расписание автобэкапа |
| `/srv/tproxy-site` | публичный сайт |
| `/opt/tgwebproxyr/docker/.env` | Compose env |
| `/opt/tgwebproxyr/backups/` | архивы |
