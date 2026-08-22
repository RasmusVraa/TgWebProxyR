# Устранение проблем

## Сертификат / HTTPS не поднимается

- A-запись указывает на **этот** VPS  
- Нет Cloudflare/CDN на первом деплое  
- Открыты TCP **80** и **443**  
- Лишний/битый AAAA лучше убрать  

```bash
sudo tgwebproxyr status
curl -fsSk https://ВАШ_ДОМЕН/ -o /dev/null && echo OK
```

## health / readyz / metrics down

```bash
sudo tgwebproxyr health
sudo tgwebproxyr status
sudo tgwebproxyr logs
sudo tgwebproxyr doctor
curl -fsS http://127.0.0.1:8081/healthz
curl -fsS http://127.0.0.1:8081/readyz
curl -fsS http://127.0.0.1:8081/metrics | head
```

Docker: admin проброшен на `127.0.0.1:8081`.  
В боте «Метрики недоступны» = тот же `:8081` не отвечает.

## Клиент «Connecting…» / web transport

- Desktop ≥ 7.1.1  
- Hostname и secret **точно** как в `link`  
- Сайт открывается по HTTPS  
- Для **нового** пользователя — см. ниже  

## Новый пользователь не коннектится

Нужны профили в **relay** и все secrets в **MTProxy** (`-S` на каждый). С **v1.6.7** это делает `secret apply`.

```bash
sudo tgwebproxyr update          # ≥ 1.6.7
sudo tgwebproxyr secret apply
sudo tgwebproxyr docker logs mtproxy 40
# ожидайте: mtproxy -S count: N
curl -fsS http://127.0.0.1:8081/healthz
```

Если `/etc/tgwebproxyr/profiles.json` — **каталог** (баг bind-mount):

```bash
sudo rm -rf /etc/tgwebproxyr/profiles.json
sudo tgwebproxyr secret apply
```

Подробнее: [[Users]].

## MTProxy не ходит в Telegram (Updating… / Docker)

За NAT или в Docker MTProxy нужен `--nat-info local:public`. С **v1.6.12** entrypoint/wrapper выставляют его сами; в логах:

```bash
sudo tgwebproxyr docker logs mtproxy 30
# >> mtproxy --nat-info 172.18.0.2:1.2.3.4
```

Вручную (если авто-IP неверен):

```bash
# в /opt/tgwebproxyr/docker/.env или settings.env
MTPROXY_NAT_INFO=192.168.1.10:203.0.113.5
# или только внешний:
MTPROXY_EXTERNAL_IP=203.0.113.5
# отключить:
MTPROXY_NAT_INFO=off
sudo tgwebproxyr secret apply   # Docker: recreate стека
```

## Pull образов «завис»

С v1.5.1 есть живой прогресс:

```bash
tail -f /tmp/tgwebproxyr-bootstrap.log
sudo tgwebproxyr docker pull
```

Если GHCR недоступен — сборка из release-бинарников (дольше).

## Не x86_64

Stock MTProxy официально под amd64. Нужен x86_64 VPS.

## Полный сброс

```bash
sudo tgwebproxyr backup create
sudo tgwebproxyr uninstall
# затем install.sh снова
```
