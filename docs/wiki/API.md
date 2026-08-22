# Shop API

REST для внешних магазинов и скриптов: пользователи, ссылки, трафик.

Актуально с **v1.6.6+**. После create/delete вызывается `secret apply` (relay + все `-S` у MTProxy).  
`/v1/traffic` с **v1.6.12** отдаёт `users[]` (сессии / байты по профилю), если relay уже с патчем metrics.

## Установка

```bash
sudo tgwebproxyr api setup
sudo tgwebproxyr api token     # Bearer
sudo tgwebproxyr api status
sudo tgwebproxyr api rotate    # новый token
```

Слушает только **127.0.0.1:8787**. Наружу — свой reverse proxy + TLS + firewall.

Файлы: `/etc/tgwebproxyr/api.env`, unit `tgwebproxyr-api.service`.

## Auth

```http
Authorization: Bearer <TWPR_API_TOKEN>
```

или `X-Api-Token: <token>`.

`GET /v1/health` — без auth.

## Endpoints

| Method | Path | Описание |
| --- | --- | --- |
| GET | `/v1/health` | liveness |
| GET | `/v1/status` | hostname, число users, mode |
| GET | `/v1/users` | список + ссылки |
| POST | `/v1/users` | `{"name":"alice"}` |
| GET | `/v1/users/{name}` | профиль |
| GET | `/v1/users/{name}/link` | tg / https |
| PATCH | `/v1/users/{name}` | `{"name":"bob"}` rename |
| DELETE | `/v1/users/{name}` | удалить (не `default`) |
| GET | `/v1/traffic` | всего + `users[]` (сессии / ↑ / ↓ по профилю) |

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
  -X PATCH -H "Content-Type: application/json" \
  -d '{"name":"shop_user2"}' \
  http://127.0.0.1:8787/v1/users/shop_user1

curl -s -H "Authorization: Bearer $TOKEN" \
  -X DELETE \
  http://127.0.0.1:8787/v1/users/shop_user2

curl -s -H "Authorization: Bearer $TOKEN" \
  http://127.0.0.1:8787/v1/traffic
```

См. также: [[Users]], [[CLI]].
