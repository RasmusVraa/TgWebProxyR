# Telegram-бот

Удалённое управление прокси (статус, ссылки, бэкапы и т.д.).

## Настройка

```bash
sudo tgwebproxyr bot setup
```

1. Создайте бота у [@BotFather](https://t.me/BotFather), скопируйте **token**.  
2. Введите token в мастер.  
3. Откройте бота в Telegram и отправьте `/start`.  
4. Admin chat id подхватится автоматически (как в ProxyL).

Файл: `/etc/tgwebproxyr/bot.env` (`BOT_TOKEN`, `ALLOWED_CHAT_IDS`).

## Управление

```bash
tgwebproxyr bot status
tgwebproxyr bot update      # подтянуть код бота с GitHub
tgwebproxyr bot restart
tgwebproxyr bot logs
tgwebproxyr bot menu        # подменю
```

Служба: `tgwebproxyr-bot.service`.

## Безопасность

- Отвечает только chat id из `ALLOWED_CHAT_IDS`.  
- Не публикуйте token; при утечке — `/revoke` у BotFather.

## Пользователи и трафик

- **➕ Добавить** — бот спросит имя, создаст secret и применит к Docker/Native.
- Переименование и удаление — в карточке пользователя.
- **📊 Трафик** — сессии и байты из `http://127.0.0.1:8081/metrics`.

Внешним магазинам: [[API]].
