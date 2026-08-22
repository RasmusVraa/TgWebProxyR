#!/usr/bin/env python3
"""TgWebProxyR Telegram bot — management UI for WEB proxy."""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

STATE_DIR = Path(os.environ.get("TWPR_STATE_DIR", "/etc/tgwebproxyr"))
BOT_ENV = STATE_DIR / "bot.env"
SETTINGS = STATE_DIR / "settings.env"
PROFILES = Path("/etc/tproxy-server/profiles.json")
CONFIG = Path("/etc/tproxy-server/config.json")
BACKUP_DIR = Path(os.environ.get("TWPR_BACKUP_DIR", "/opt/tgwebproxyr/backups"))
API = "https://api.telegram.org/bot{token}/{method}"


def load_dotenv(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip().strip("'").strip('"')
    return out


def save_bot_env(data: dict[str, str]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    lines = ["# TgWebProxyR bot config", f"BOT_TOKEN={data.get('BOT_TOKEN', '')}", f"ALLOWED_CHAT_IDS={data.get('ALLOWED_CHAT_IDS', '')}"]
    BOT_ENV.write_text("\n".join(lines) + "\n", encoding="utf-8")
    os.chmod(BOT_ENV, 0o600)


CFG = {**load_dotenv(SETTINGS), **load_dotenv(BOT_ENV)}
TOKEN = CFG.get("BOT_TOKEN", "")
ALLOWED = {x.strip() for x in CFG.get("ALLOWED_CHAT_IDS", "").split(",") if x.strip()}


def hostname() -> str:
    return CFG.get("TWPR_HOSTNAME", "") or "—"


def secret_default() -> str:
    return CFG.get("TWPR_SECRET", "")


def admin_port() -> str:
    return CFG.get("TWPR_PORT_ADMIN", "8081")


def https_port() -> str:
    return CFG.get("TWPR_PORT_HTTPS", "443")


def api(method: str, payload: dict[str, Any] | None = None) -> dict[str, Any]:
    url = API.format(token=TOKEN, method=method)
    data = None
    headers = {}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method="POST" if data else "GET")
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def allowed(chat_id: int | str) -> bool:
    if not ALLOWED:
        return True
    return str(chat_id) in ALLOWED


def kb(rows: list[list[tuple[str, str]]]) -> dict[str, Any]:
    return {
        "inline_keyboard": [[{"text": t, "callback_data": d} for t, d in row] for row in rows]
    }


def main_menu_kb() -> dict[str, Any]:
    return kb(
        [
            [("ℹ️ Статус", "status"), ("🚦 Прокси", "proxy")],
            [("👥 Пользователи", "users"), ("🔗 Ссылки", "links")],
            [("📊 Трафик", "traffic"), ("📡 Доступность", "avail")],
            [("💾 Бэкапы", "backups"), ("⚙️ Настройки", "settings")],
            [("🔄 Doctor", "doctor")],
        ]
    )


def back_kb() -> dict[str, Any]:
    return kb([[("⬅️ Меню", "menu")]])


def svc(name: str) -> str:
    try:
        r = subprocess.run(["systemctl", "is-active", name], capture_output=True, text=True, timeout=5)
        return (r.stdout or r.stderr or "unknown").strip()
    except Exception:
        return "unknown"


def curl_ok(url: str) -> bool:
    try:
        urllib.request.urlopen(url, timeout=3)
        return True
    except Exception:
        return False


def fmt_bytes(n: float) -> str:
    units = ["B", "KB", "MB", "GB", "TB"]
    v = float(n)
    for u in units:
        if v < 1024 or u == units[-1]:
            if u == "B":
                return f"{int(v)} {u}"
            return f"{v:.1f} {u}"
        v /= 1024
    return f"{n} B"


def load_profiles() -> list[dict[str, Any]]:
    if not PROFILES.is_file():
        return []
    try:
        data = json.loads(PROFILES.read_text(encoding="utf-8"))
        return list(data.get("profiles") or [])
    except Exception:
        return []


def save_profiles(profiles: list[dict[str, Any]]) -> None:
    PROFILES.parent.mkdir(parents=True, exist_ok=True)
    tmp = PROFILES.with_suffix(".tmp")
    tmp.write_text(json.dumps({"profiles": profiles}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.chmod(tmp, 0o400)
    tmp.replace(PROFILES)
    try:
        shutil.chown(PROFILES, user="root", group="tproxy")
    except Exception:
        pass
    subprocess.run(["systemctl", "restart", "tproxy-server"], capture_output=True, timeout=30)


def web_link(host: str, secret: str) -> str:
    q = urllib.parse.urlencode({"server": host, "secret": secret})
    return f"https://t.me/webproxy?{q}"


def tg_link(host: str, secret: str) -> str:
    q = urllib.parse.urlencode({"server": host, "secret": secret})
    return f"tg://webproxy?{q}"


def text_status() -> str:
    host = hostname()
    relay = svc("tproxy-server")
    mp = svc("mtproxy")
    caddy = svc("caddy")
    hz = curl_ok(f"http://127.0.0.1:{admin_port()}/healthz")
    rz = curl_ok(f"http://127.0.0.1:{admin_port()}/readyz")
    mark = "🟢" if rz else ("🟡" if hz else "🔴")
    return (
        f"<b>TgWebProxyR · Статус</b>\n\n"
        f"{mark} host: <code>{host}</code>\n"
        f"tproxy-server: <code>{relay}</code>\n"
        f"mtproxy: <code>{mp}</code>\n"
        f"caddy: <code>{caddy}</code>\n"
        f"healthz: <code>{'ok' if hz else 'fail'}</code> · "
        f"readyz: <code>{'ok' if rz else 'fail'}</code>\n"
        f"HTTPS порт: <code>{https_port()}</code>"
    )


def text_proxy() -> str:
    host = hostname()
    return (
        f"<b>TgWebProxyR · Прокси</b>\n\n"
        f"Тип: <b>WEB</b>\n"
        f"Hostname: <code>{host}</code>\n"
        f"HTTP: <code>{CFG.get('TWPR_PORT_HTTP', '80')}</code>\n"
        f"HTTPS: <code>{CFG.get('TWPR_PORT_HTTPS', '443')}</code>\n"
        f"relay: <code>{CFG.get('TWPR_PORT_RELAY', '8080')}</code>\n"
        f"admin: <code>{CFG.get('TWPR_PORT_ADMIN', '8081')}</code>\n"
        f"mtproxy: <code>{CFG.get('TWPR_PORT_MTPROXY', '2398')}</code>\n\n"
        f"Клиент: Telegram Desktop ≥ 7.1.1 → Add proxy → WEB"
    )


def text_users() -> str:
    profiles = load_profiles()
    if not profiles:
        return "<b>Пользователи</b>\n\nПрофили не найдены. Добавьте secret через бота или <code>tgwebproxyr secret add</code>."
    lines = ["<b>Пользователи / secrets</b>\n"]
    for p in profiles:
        name = p.get("name", "?")
        sec = str(p.get("secret", ""))
        short = sec[:8] + "…" if len(sec) > 8 else sec
        lines.append(f"• <b>{name}</b> · <code>{short}</code> · {p.get('backend', '')}")
    lines.append(f"\nВсего: <b>{len(profiles)}</b>")
    return "\n".join(lines)


def text_links() -> str:
    host = hostname()
    profiles = load_profiles()
    if not profiles and secret_default():
        profiles = [{"name": "default", "secret": secret_default()}]
    if not profiles:
        return "<b>Ссылки</b>\n\nНет secret."
    parts = ["<b>Ссылки WEB proxy</b>\n"]
    for p in profiles:
        name = p.get("name", "user")
        sec = p.get("secret", "")
        parts.append(f"<b>{name}</b>")
        parts.append(f"<code>{tg_link(host, sec)}</code>")
        parts.append(f"<code>{web_link(host, sec)}</code>\n")
    return "\n".join(parts)


def parse_mtproxy_stats() -> str:
    try:
        with urllib.request.urlopen("http://127.0.0.1:8888/stats", timeout=3) as resp:
            raw = resp.read().decode("utf-8", errors="replace")
    except Exception as e:
        return f"<b>Трафик</b>\n\nСтаты MTProxy недоступны (<code>:8888/stats</code>).\n<code>{e}</code>"

    # Keep a compact view; official stats are key=value / special lines
    lines = [ln for ln in raw.splitlines() if ln.strip()][:40]
    body = "\n".join(lines) if lines else raw[:1500]
    return f"<b>Трафик / MTProxy stats</b>\n\n<pre>{body[:3500]}</pre>"


def text_traffic() -> str:
    profiles = load_profiles()
    # Stock MTProxy does not expose clean per-user WEB multiplex stats; show profiles + raw stats
    header = "<b>Трафик</b>\n\n"
    table = ["Имя".ljust(12) + "backend"]
    for p in profiles:
        table.append(f"{str(p.get('name', '?'))[:12].ljust(12)}{p.get('backend', '')}")
    block = "\n".join(table)
    extra = parse_mtproxy_stats()
    metrics = ""
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{admin_port()}/metrics", timeout=3) as resp:
            m = resp.read().decode("utf-8", errors="replace")
        keep = [ln for ln in m.splitlines() if ln and not ln.startswith("#")][:25]
        if keep:
            metrics = "\n\n<b>relay metrics</b>\n<pre>" + "\n".join(keep)[:2000] + "</pre>"
    except Exception:
        pass
    return (
        header
        + f"<pre>{block}</pre>\n"
        + f"Профилей: <b>{len(profiles)}</b>\n\n"
        + extra
        + metrics
    )


def text_avail() -> str:
    host = hostname()
    checks = []
    if host and host != "—":
        url = f"https://{host}/" if https_port() == "443" else f"https://{host}:{https_port()}/"
        try:
            urllib.request.urlopen(url, timeout=8)
            checks.append(f"🟢 HTTPS сайт: <code>{url}</code>")
        except Exception as e:
            checks.append(f"🔴 HTTPS сайт: <code>{url}</code>\n<code>{e}</code>")
    hz = curl_ok(f"http://127.0.0.1:{admin_port()}/healthz")
    rz = curl_ok(f"http://127.0.0.1:{admin_port()}/readyz")
    checks.append(("🟢" if hz else "🔴") + " local healthz")
    checks.append(("🟢" if rz else "🔴") + " local readyz (backend)")
    checks.append(("🟢" if svc("mtproxy") == "active" else "🔴") + " mtproxy.service")
    checks.append(("🟢" if svc("caddy") == "active" else "🔴") + " caddy.service")
    return "<b>Доступность</b>\n\n" + "\n".join(checks)


def do_backup() -> str:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    dest = BACKUP_DIR / f"twpr-{stamp}"
    dest.mkdir(parents=True)
    for src in (
        SETTINGS,
        BOT_ENV,
        PROFILES,
        CONFIG,
        Path("/etc/caddy/Caddyfile"),
        Path("/etc/mtproxy/mtproxy.env"),
    ):
        if src.is_file():
            shutil.copy2(src, dest / src.name)
    meta = {
        "created_at": stamp,
        "hostname": hostname(),
        "version": Path("/opt/tgwebproxyr/version").read_text(encoding="utf-8").strip()
        if Path("/opt/tgwebproxyr/version").is_file()
        else "?",
    }
    (dest / "meta.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    return str(dest)


def list_backups() -> list[Path]:
    if not BACKUP_DIR.is_dir():
        return []
    return sorted([p for p in BACKUP_DIR.iterdir() if p.is_dir()], reverse=True)


def text_backups() -> str:
    items = list_backups()[:15]
    if not items:
        return "<b>Бэкапы</b>\n\nПока пусто. Нажмите «Создать бэкап»."
    lines = ["<b>Бэкапы</b>\n"]
    for p in items:
        lines.append(f"• <code>{p.name}</code>")
    lines.append(f"\nКаталог: <code>{BACKUP_DIR}</code>")
    return "\n".join(lines)


def text_settings() -> str:
    chats = CFG.get("ALLOWED_CHAT_IDS", "") or "(все — не рекомендуется)"
    tok = TOKEN
    masked = (tok[:6] + "…" + tok[-4:]) if len(tok) > 12 else "(не задан)"
    return (
        f"<b>Настройки бота</b>\n\n"
        f"Token: <code>{masked}</code>\n"
        f"Allowed chat ids:\n<code>{chats}</code>\n\n"
        f"Файл: <code>{BOT_ENV}</code>\n"
        f"Изменить: <code>tgwebproxyr bot setup</code>"
    )


def run_doctor() -> str:
    try:
        r = subprocess.run(
            ["/opt/tgwebproxyr/tgwebproxyr.sh", "doctor"],
            capture_output=True,
            text=True,
            timeout=180,
        )
        out = (r.stdout or "") + (r.stderr or "")
        out = out[-3500:] if out else f"exit={r.returncode}"
        return f"<b>Doctor</b>\n\n<pre>{out}</pre>"
    except Exception as e:
        return f"<b>Doctor</b>\n\n<code>{e}</code>"


def send_message(chat_id: int, text: str, reply_markup: dict[str, Any] | None = None) -> None:
    payload: dict[str, Any] = {
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True,
    }
    if reply_markup:
        payload["reply_markup"] = reply_markup
    api("sendMessage", payload)


def edit_message(chat_id: int, message_id: int, text: str, reply_markup: dict[str, Any] | None = None) -> None:
    payload: dict[str, Any] = {
        "chat_id": chat_id,
        "message_id": message_id,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True,
    }
    if reply_markup:
        payload["reply_markup"] = reply_markup
    try:
        api("editMessageText", payload)
    except urllib.error.HTTPError:
        send_message(chat_id, text, reply_markup)


def answer_cb(cb_id: str) -> None:
    try:
        api("answerCallbackQuery", {"callback_query_id": cb_id})
    except Exception:
        pass


def handle_callback(cq: dict[str, Any]) -> None:
    data = cq.get("data") or ""
    msg = cq.get("message") or {}
    chat = (msg.get("chat") or {}).get("id")
    mid = msg.get("message_id")
    cb_id = cq.get("id")
    if chat is None:
        return
    if not allowed(chat):
        answer_cb(cb_id)
        send_message(chat, "⛔ Нет доступа.")
        return
    answer_cb(cb_id)

    if data == "menu":
        edit_message(
            chat,
            mid,
            "<b>TgWebProxyR</b>\nВыберите раздел. Команды: /help",
            main_menu_kb(),
        )
        return

    mapping = {
        "status": (text_status, back_kb),
        "proxy": (text_proxy, back_kb),
        "users": (text_users, lambda: kb([[("➕ Добавить secret", "user_add")], [("⬅️ Меню", "menu")]])),
        "links": (text_links, back_kb),
        "traffic": (text_traffic, back_kb),
        "avail": (text_avail, back_kb),
        "settings": (text_settings, back_kb),
        "doctor": (run_doctor, back_kb),
        "backups": (
            text_backups,
            lambda: kb([[("🆕 Создать бэкап", "backup_create")], [("⬅️ Меню", "menu")]]),
        ),
    }

    if data == "backup_create":
        path = do_backup()
        edit_message(chat, mid, f"<b>Бэкап создан</b>\n<code>{path}</code>", back_kb())
        return

    if data == "user_add":
        # generate secret and append profile
        import secrets as pysecrets

        sec = pysecrets.token_hex(16)
        profiles = load_profiles()
        name = f"user{int(time.time()) % 100000}"
        backend = f"127.0.0.1:{CFG.get('TWPR_PORT_MTPROXY', '2398')}"
        profiles.append({"name": name, "secret": sec, "backend": backend, "carrier_mode": "https"})
        try:
            save_profiles(profiles)
            host = hostname()
            edit_message(
                chat,
                mid,
                f"<b>Добавлен {name}</b>\n"
                f"secret: <code>{sec}</code>\n\n"
                f"<code>{tg_link(host, sec)}</code>\n"
                f"<code>{web_link(host, sec)}</code>",
                back_kb(),
            )
        except Exception as e:
            edit_message(chat, mid, f"Ошибка: <code>{e}</code>", back_kb())
        return

    if data in mapping:
        fn, mk = mapping[data]
        edit_message(chat, mid, fn(), mk())
        return


def handle_message(msg: dict[str, Any]) -> None:
    chat = (msg.get("chat") or {}).get("id")
    text = (msg.get("text") or "").strip()
    if chat is None:
        return
    if not allowed(chat):
        send_message(chat, "⛔ Нет доступа. Добавьте ваш chat id в ALLOWED_CHAT_IDS.")
        return

    if text.startswith("/start") or text.startswith("/menu") or text == "меню":
        send_message(chat, "<b>TgWebProxyR</b>\nВыберите раздел. Команды: /help", main_menu_kb())
        return
    if text.startswith("/help"):
        send_message(
            chat,
            "<b>Команды</b>\n"
            "/menu — главное меню\n"
            "/status /links /users /traffic /backups /doctor\n",
            main_menu_kb(),
        )
        return
    if text.startswith("/status"):
        send_message(chat, text_status(), back_kb())
        return
    if text.startswith("/links"):
        send_message(chat, text_links(), back_kb())
        return
    if text.startswith("/users"):
        send_message(chat, text_users(), back_kb())
        return
    if text.startswith("/traffic"):
        send_message(chat, text_traffic(), back_kb())
        return
    if text.startswith("/backups"):
        send_message(chat, text_backups(), kb([[("🆕 Создать бэкап", "backup_create")], [("⬅️ Меню", "menu")]]))
        return
    if text.startswith("/doctor"):
        send_message(chat, run_doctor(), back_kb())
        return
    if text.startswith("/chatid"):
        send_message(chat, f"Ваш chat id: <code>{chat}</code>")
        return

    send_message(chat, "Не понял. Откройте /menu", main_menu_kb())


def main() -> None:
    global CFG, TOKEN, ALLOWED
    CFG = {**load_dotenv(SETTINGS), **load_dotenv(BOT_ENV)}
    TOKEN = CFG.get("BOT_TOKEN", "")
    ALLOWED = {x.strip() for x in CFG.get("ALLOWED_CHAT_IDS", "").split(",") if x.strip()}
    if not TOKEN:
        raise SystemExit("BOT_TOKEN не задан в /etc/tgwebproxyr/bot.env — tgwebproxyr bot setup")

    offset = 0
    print(f"TgWebProxyR bot started · allow={ALLOWED or 'ANY'}", flush=True)
    while True:
        try:
            res = api(
                "getUpdates",
                {"timeout": 50, "offset": offset, "allowed_updates": ["message", "callback_query"]},
            )
            for upd in res.get("result") or []:
                offset = max(offset, int(upd["update_id"]) + 1)
                if "callback_query" in upd:
                    handle_callback(upd["callback_query"])
                elif "message" in upd:
                    handle_message(upd["message"])
        except Exception as e:
            print(f"loop error: {e}", flush=True)
            time.sleep(3)


if __name__ == "__main__":
    main()
