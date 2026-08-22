# Устранение проблем

## Сертификат / HTTPS не поднимается

- A-запись домена указывает на **этот** VPS  
- Нет Cloudflare/CDN на первом деплое  
- Открыты TCP **80** и **443**  
- Лишний/битый AAAA лучше убрать  

```bash
sudo tgwebproxyr status
curl -fsSk https://ВАШ_ДОМЕН/ -o /dev/null && echo OK
```

## health / readyz down

```bash
sudo tgwebproxyr status
sudo tgwebproxyr logs
sudo tgwebproxyr doctor
curl -fsS http://127.0.0.1:8081/healthz
curl -fsS http://127.0.0.1:8081/readyz
```

Docker: admin проброшен на `127.0.0.1:8081`.

## Клиент «Connecting…»

- Desktop ≥ 7.1.1  
- Hostname и secret **точно** как в `tgwebproxyr link`  
- Сайт с хоста открывается по HTTPS  

## Новый пользователь не коннектится (Docker)

Старые установки не монтировали `profiles.json` в relay. Обновите и пересоздайте relay:

```bash
sudo tgwebproxyr update
sudo tgwebproxyr secret apply
# или:
cd /opt/tgwebproxyr/docker && docker compose up -d --force-recreate --no-deps relay
```

Если `/etc/tgwebproxyr/profiles.json` оказался **каталогом** (баг bind-mount без файла) — удалите каталог, затем:

```bash
sudo tgwebproxyr secret apply
```

## Pull образов «завис»

С v1.5.1 есть живой прогресс. Смотрите также:

```bash
tail -f /tmp/tgwebproxyr-bootstrap.log
sudo tgwebproxyr docker pull
```

Если GHCR недоступен — compose соберёт из release-бинарников (дольше).

## Не x86_64

Stock MTProxy официально под amd64. Нужен x86_64 VPS.

## Полный сброс

```bash
sudo tgwebproxyr backup create
sudo tgwebproxyr uninstall
# затем install.sh снова
```
