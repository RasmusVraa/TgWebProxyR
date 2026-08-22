# Shop API

REST API для внешних магазинов и скриптов: создание пользователей, ссылки, трафик.

## Установка

```bash
sudo tgwebproxyr api setup
sudo tgwebproxyr api token    # показать Bearer-токен
```

Слушает только **127.0.0.1:8787** (не торчит наружу). Для доступа с другого хоста — свой reverse proxy + TLS + firewall.

Файлы: `/etc/tgwebproxyr/api.env`, unit `tgwebproxyr-api.service`.

## Auth

```http
Authorization: Bearer <TWPR_API_TOKEN>
```

или заголовок `X-Api-Token: <token>`.

## Endpoints

| Method | Path | Описание |
| --- | --- | --- |
| GET | `/v1/health` | без auth |
| GET | `/v1/status` | hostname, число users |
| GET | `/v1/users` | список + ссылки |
| POST | `/v1/users` | `{"name":"alice"}` → создать |
| GET | `/v1/users/{name}` | профиль |
| GET | `/v1/users/{name}/link` | tg / https ссылки |
| PATCH | `/v1/users/{name}` | `{"name":"bob"}` → rename |
| DELETE | `/v1/users/{name}` | удалить (не default) |
| GET | `/v1/traffic` | метрики relay |

## Примеры

```bash
TOKEN=$(sudo tgwebproxyr api token)

curl -s -H "Authorization: Bearer $TOKEN" \
  http://127.0.0.1:8787/v1/users

curl -s -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"shop_user1"}' \
  http://127.0.0.1:8787/v1/users

curl -s -H "Authorization: Bearer $TOKEN" \
  http://127.0.0.1:8787/v1/users/shop_user1/link
```

После create/delete профили сразу применяются к Docker/Native движку (`secret apply`).
