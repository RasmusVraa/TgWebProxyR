# Shop API

REST для внешних магазинов и скриптов: пользователи, ссылки, трафик, **лимиты**.

Актуально с **v1.6.6+**. Квоты — с **v1.6.13**. После create/delete вызывается `secret apply`.

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
| GET | `/v1/users` | список + ссылки + quota/used/enabled |
| POST | `/v1/users` | `{"name":"alice","quota":"10G"}` |
| GET | `/v1/users/{name}` | профиль + квота |
| GET | `/v1/users/{name}/link` | tg / https |
| PATCH | `/v1/users/{name}` | rename / `quota` / `enabled` / `reset_usage` |
| DELETE | `/v1/users/{name}` | удалить (не `default`) |
| GET | `/v1/traffic` | live + used/quota по пользователям |

### PATCH примеры

```json
{"name":"bob"}
{"quota":"5G"}
{"quota_bytes":5368709120}
{"enabled":false}
{"reset_usage":true}
{"quota":"unlimited","enabled":true}
```

## Примеры

```bash
TOKEN=$(sudo tgwebproxyr api token)

curl -s -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"shop_user1","quota":"10G"}' \
  http://127.0.0.1:8787/v1/users

curl -s -X PATCH -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"enabled":true,"quota":"5G"}' \
  http://127.0.0.1:8787/v1/users/shop_user1

curl -s -H "Authorization: Bearer $TOKEN" \
  http://127.0.0.1:8787/v1/traffic
```

См. также: [[Users]], [[CLI]].
