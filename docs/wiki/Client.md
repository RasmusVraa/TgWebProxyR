# Подключение клиента

Нужен **Telegram Desktop 7.1.1+**.

## Через ссылку

```bash
sudo tgwebproxyr link              # default
sudo tgwebproxyr secret link alice # именованный пользователь
```

Откройте `tg://webproxy?…` на машине с Desktop или вставьте в **Add proxy → WEB**.

## Вручную

**Settings → Advanced → Connection type → Add proxy → WEB**

| Поле | Значение |
| --- | --- |
| Hostname | домен без `https://` и без порта |
| Secret | 32 hex (`secret show` / карточка в боте) |

Порт всегда **443**, схема всегда **HTTPS** — клиент их не спрашивает.

## Проверка сайта

В браузере должен открываться публичный сайт: `https://ваш-домен/`.  
Это нормально: bridge активируется только из WebView с правильным secret.

## Несколько пользователей

У каждого свой secret и своя ссылка на **том же** hostname. См. [[Users]].

## Клиенты

| Клиент | Статус (upstream) |
| --- | --- |
| Desktop | поддерживается |
| Android | experimental PoC в tproxy-server |
| iOS | в планах upstream |

Если *«built-in web transport couldn't connect»* — [[Troubleshooting]].
