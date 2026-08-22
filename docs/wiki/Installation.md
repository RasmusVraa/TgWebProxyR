# Установка

## One-liner

```bash
wget -qO /tmp/twpr.sh \
  https://raw.githubusercontent.com/RasmusVraa/TgWebProxyR/main/install.sh \
  && sudo bash /tmp/twpr.sh
```

Не используйте `curl … | bash` — мастеру нужен TTY.

## Что спросит мастер

1. **Режим**: Docker быстро / Docker расширенно / Native быстро / Native расширенно  
2. **Домен** (DNS A на VPS, без CDN)  
3. **Email** для Let's Encrypt  
4. Secret — генерируется сам (в advanced можно задать свой)

## Флаги `install.sh` / `setup`

| Флаг | Значение |
| --- | --- |
| `--docker` | Compose + образы GHCR |
| `--native` | systemd + upstream install |
| `--quick` | минимум вопросов |
| `--advanced` | порты / workers / secret |
| `--yes` | без подтверждений |

Переменные окружения: `TWPR_HOSTNAME`, `TWPR_EMAIL`, `TWPR_SECRET`, `TWPR_YES=1`.

### Примеры

```bash
# Docker без вопросов
sudo TWPR_HOSTNAME=proxy.example.com \
     TWPR_EMAIL=you@example.com \
     TWPR_YES=1 bash /tmp/twpr.sh --docker --quick

# Native расширенно
sudo bash /tmp/twpr.sh --native --advanced

# Уже установлено — снова мастер
sudo tgwebproxyr setup --docker --quick
```

## После установки

```bash
sudo tgwebproxyr          # меню
sudo tgwebproxyr link     # ссылки
sudo tgwebproxyr status
```

Для non-root создаётся алиас в `/etc/profile.d/tgwebproxyr.sh`  
(`tgwebproxyr` → `sudo tgwebproxyr`). Примените: `source /etc/profile.d/tgwebproxyr.sh`.

## Требования

- Ubuntu 22.04+ / Debian 12+, **x86_64**
- Публичный IPv4, DNS A, порты **80** и **443**
- Root
