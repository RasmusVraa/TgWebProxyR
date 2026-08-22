# Подключение клиента

Нужен **Telegram Desktop 7.1.1+**.

## Через ссылку

```bash
sudo tgwebproxyr link
```

Откройте `tg://webproxy?…` на машине с Desktop.

## Вручную

**Settings → Advanced → Connection type → Add proxy → WEB**

| Поле | Значение |
| --- | --- |
| Hostname | ваш домен без `https://` и без порта |
| Secret | 32 hex из `tgwebproxyr secret show` |

Порт всегда **443**, схема всегда **HTTPS** — клиент их не спрашивает.

## Проверка сайта

В браузере должен открываться публичный сайт: `https://ваш-домен/`.  
Это нормально: bridge активируется только из WebView с правильным secret.

## Клиенты

| Клиент | Статус (upstream) |
| --- | --- |
| Desktop | поддерживается |
| Android | experimental PoC в tproxy-server |
| iOS | в планах upstream |
