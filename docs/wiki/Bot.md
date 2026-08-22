# Telegram-бот

Удалённое управление: статус, прокси, пользователи, ссылки, логи, трафик, бэкапы.

## Настройка

```bash
sudo tgwebproxyr bot setup
```

1. Создайте бота у [@BotFather](https://t.me/BotFather), скопируйте **token**.  
2. Введите token в мастер.  
3. Откройте бота → отправьте `/start`.  
4. Admin chat id подхватится автоматически.

Файл: `/etc/tgwebproxyr/bot.env` (`BOT_TOKEN`, `ALLOWED_CHAT_IDS`).  
Служба: `tgwebproxyr-bot.service`.

## Управление

```bash
tgwebproxyr bot status
tgwebproxyr bot update      # код с диска репо / GitHub
tgwebproxyr bot restart
tgwebproxyr bot logs
tgwebproxyr bot menu
```

## Возможности

| Раздел | Что делает |
| --- | --- |
| Статус | hostname, режим, кратко по сервисам |
| Прокси | start / stop / restart |
| Пользователи | список, карточка, ➕ с именем, rename, delete |
| Ссылки | tg:// и https://t.me/webproxy по страницам |
| Логи | хвост journalctl / compose |
| Трафик | всего + по пользователям + used/quota (≥1.6.13) |
| Бэкапы | создать, авто (hourly/daily/monthly), restore |

В карточке пользователя: лимит, вкл/выкл, сброс usage.

Команды: `/menu` `/status` `/proxy` `/users` `/links` `/logs` `/traffic` `/backups`.

Если «Трафик» пустой при живом health — обновите до ≥1.6.11 (admin-proxy).  
Если нет разбивки по пользователям — relay ≥1.6.12 и `tgwebproxyr update` + `secret apply`.

## Безопасность

- Отвечает только chat id из `ALLOWED_CHAT_IDS`.  
- Не публикуйте token; при утечке — `/revoke` у BotFather.

Магазинам без бота: [[API]]. Пользователи: [[Users]].
