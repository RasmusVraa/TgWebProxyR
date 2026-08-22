# CLI

Команда: `tgwebproxyr` (от non-root — через sudo / алиас).

## Меню

```bash
tgwebproxyr
# или
tgwebproxyr menu
```

Пункты:

1. Ссылки  
2. Статус  
3. Управление (start / stop / restart / doctor)  
4. Логи  
5. Пользователи / secrets  
6. Настройки  
7. Telegram-бот  
8. Обновление и бэкапы  
9. Установка / переустановка  
u. Удалить  

## Прокси

```bash
tgwebproxyr start
tgwebproxyr stop
tgwebproxyr restart
tgwebproxyr status
tgwebproxyr link
tgwebproxyr logs              # compose или journalctl
tgwebproxyr logs relay 200    # Docker: сервис + хвост
tgwebproxyr doctor
```

## Установка

```bash
tgwebproxyr setup
tgwebproxyr setup --docker --quick
tgwebproxyr setup --native --advanced --hostname proxy.example.com --email a@b.c --yes
tgwebproxyr install …         # синоним setup
tgwebproxyr reinstall
```

## Secrets

```bash
tgwebproxyr secret list
tgwebproxyr secret show
tgwebproxyr secret link [name]
tgwebproxyr secret rotate [name]
tgwebproxyr secret add [name]       # Docker и Native
tgwebproxyr secret rename <old> <new>
tgwebproxyr secret remove <name>
tgwebproxyr secret apply            # перечитать реестр в движок
tgwebproxyr metrics                 # трафик / сессии
tgwebproxyr metrics --raw
```

Реестр: `/etc/tgwebproxyr/profiles.json` (профиль `default` всегда первый). В Docker файл монтируется в relay.

## Бот / API / бэкапы / Docker

```bash
tgwebproxyr bot setup|update|status|start|stop|restart|logs|menu
tgwebproxyr api setup|token|status|start|stop|restart|logs
tgwebproxyr backup create|list|restore <name>|auto …
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
| `/etc/tgwebproxyr/settings.env` | состояние |
| `/etc/tgwebproxyr/bot.env` | токен бота |
| `/etc/tgwebproxyr/api.env` | Bearer token Shop API |
| `/etc/tgwebproxyr/profiles.json` | пользователи / secrets |
| `/srv/tproxy-site` | публичный сайт |
| `/opt/tgwebproxyr/docker/.env` | Compose env |
| `/opt/tgwebproxyr/backups/` | бэкапы |
