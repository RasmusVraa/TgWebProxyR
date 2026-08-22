# Бэкапы

Архивы в `/opt/tgwebproxyr/backups/` (`twpr-*.tar.gz`): settings, profiles, bot/api env, docker `.env` и связанные файлы.

## Вручную

```bash
sudo tgwebproxyr backup create
sudo tgwebproxyr backup list
sudo tgwebproxyr backup restore twpr-YYYYMMDD-….tar.gz
```

После restore обычно нужен `secret apply` / рестарт стека (restore делает это по возможности сам).

## Автобэкап

```bash
sudo tgwebproxyr backup auto hourly
sudo tgwebproxyr backup auto daily
sudo tgwebproxyr backup auto monthly
sudo tgwebproxyr backup auto off

sudo tgwebproxyr backup auto send on    # слать tar.gz админу в TG
sudo tgwebproxyr backup auto send off
```

systemd: `tgwebproxyr-autobackup.timer` + `.service`.  
Состояние: `/etc/tgwebproxyr/autobackup.env`.

## В боте

Раздел **Бэкапы**: создать, настроить авто, восстановить с подтверждением.  
При создании (и авто, если включено) файл уходит документом в чат админа.

См. [[Bot]].
