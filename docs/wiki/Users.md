# Пользователи (secrets / профили)

Несколько людей на **одном hostname** = несколько client secret.

Реестр: **`/etc/tgwebproxyr/profiles.json`**

| Имя | Роль |
| --- | --- |
| `default` | основной secret установки (`TWPR_SECRET`), нельзя удалить |
| любое другое | отдельный пользователь со своим secret и ссылкой |

## Как это применяется

1. **Relay** (`tproxy-server`) читает все профили из реестра.  
2. **MTProxy** получает **каждый** secret как отдельный `-S` (общий backend `127.0.0.1:2398`).  

Без шага 2 новый пользователь не коннектится (ошибка Desktop *web transport couldn't connect*).  
Команда `secret apply` обновляет и relay, и mtproxy (в Docker — пересоздание стека).

## CLI

```bash
sudo tgwebproxyr secret list
sudo tgwebproxyr secret add alice
sudo tgwebproxyr secret link alice
sudo tgwebproxyr secret rename alice bob
sudo tgwebproxyr secret rotate bob
sudo tgwebproxyr secret remove bob
sudo tgwebproxyr secret apply
sudo tgwebproxyr metrics
# всего + по каждому пользователю (↑ / ↓ / сессии)
```

Нужен relay **≥1.6.12** (в `/metrics` строки `tproxy_*{profile="…"}`).  
Имя: латиница, цифры, `._-` (без пробелов).

## Бот

**Пользователи → ➕** — бот спросит имя, создаст secret и вызовет apply.  
В карточке: ссылка, переименовать, удалить.

## Shop API

Создание/удаление через REST — см. [[API]].

## Проверка

```bash
# число -S должно совпадать с числом профилей
sudo tgwebproxyr docker logs mtproxy 40
# >> mtproxy -S count: 2
# >> mtproxy --nat-info …   (≥1.6.12)

curl -fsS http://127.0.0.1:8081/healthz
curl -fsS http://127.0.0.1:8081/metrics | grep 'profile='
sudo tgwebproxyr secret list
```

Если `/etc/tgwebproxyr/profiles.json` стал **каталогом** (старый bind-mount без файла) — удалите каталог и снова `secret apply`.
