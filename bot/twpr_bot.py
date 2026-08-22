#!/usr/bin/env python3
"""TgWebProxyR Telegram bot — ProxyL-style menu, fast long-poll."""
from __future__ import annotations

import json
import os
import secrets as pysecrets
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
# docker volume path may differ — also check compose mount
PROFILES_CANDIDATES = [
    PROFILES,
    Path("/opt/tgwebproxyr/docker/relay_cfg/profiles.json"),
]
CONFIG = Path("/etc/tproxy-server/config.json")
BACKUP_DIR = Path(os.environ.get("TWPR_BACKUP_DIR", "/opt/tgwebproxyr/backups"))
DOCKER_DIR = Path("/opt/tgwebproxyr/docker")
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
    BOT_ENV.write_text(
        "# TgWebProxyR bot\n"
        f"BOT_TOKEN={data.get('BOT_TOKEN', '')}\n"
        f"ALLOWED_CHAT_IDS={data.get('ALLOWED_CHAT_IDS', '')}\n",
        encoding="utf-8",
    )
    os.chmod(BOT_ENV, 0o600)


def reload_cfg() -> tuple[dict[str, str], str, set[str]]:
    cfg = {**load_dotenv(SETTINGS), **load_dotenv(BOT_ENV)}
    token = cfg.get("BOT_TOKEN", "")
    allowed = {x.strip() for x in cfg.get("ALLOWED_CHAT_IDS", "").split(",") if x.strip()}
    return cfg, token, allowed


CFG, TOKEN, ALLOWED = reload_cfg()


def is_docker() -> bool:
    return CFG.get("TWPR_DEPLOY_MODE") == "docker" or (DOCKER_DIR / ".env").is_file()


def hostname() -> str:
    h = CFG.get("TWPR_HOSTNAME", "")
    if h:
        return h
    if (DOCKER_DIR / ".env").is_file():
        return load_dotenv(DOCKER_DIR / ".env").get("TWPR_HOSTNAME", "—")
    return "—"


def secret_default() -> str:
    return CFG.get("TWPR_SECRET", "") or load_dotenv(DOCKER_DIR / ".env").get("TWPR_SECRET", "")


def admin_port() -> str:
    return CFG.get("TWPR_PORT_ADMIN", "8081")


def api(method: str, payload: dict[str, Any] | None = None, timeout: float = 12) -> dict[str, Any]:
    url = API.format(token=TOKEN, method=method)
    data = None
    headers: dict[str, str] = {}
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers, method="POST" if data else "GET")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def allowed(chat_id: int | str) -> bool:
    if not ALLOWED:
        return False
    return str(chat_id) in ALLOWED


def kb(rows: list[list[tuple[str, str]]]) -> dict[str, Any]:
    return {"inline_keyboard": [[{"text": t, "callback_data": d} for t, d in row] for row in rows]}


def main_menu_kb() -> dict[str, Any]:
    # как ProxyL / MTProxyL
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


def sh(cmd: list[str], timeout: float = 8) -> str:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return ((r.stdout or "") + (r.stderr or "")).strip()
    except Exception as e:
        return str(e)


def docker_ps_line(svc: str) -> str:
    out = sh(
        [
            "docker",
            "compose",
            "-f",
            str(DOCKER_DIR / "docker-compose.yml"),
            "--env-file",
            str(DOCKER_DIR / ".env"),
            "ps",
            "-a",
            "--format",
            "{{.Status}}",
            svc,
        ],
        timeout=6,
    )
    return out.splitlines()[0] if out else "missing"


def svc(name: str) -> str:
    if is_docker():
        mapping = {"tproxy-server": "relay", "mtproxy": "mtproxy", "caddy": "caddy"}
        dname = mapping.get(name, name)
        st = docker_ps_line(dname).lower()
        if "up" in st or "running" in st:
            return "running" if "unhealthy" not in st else "unhealthy"
        if "exit" in st:
            return "exited"
        return st or "missing"
    return sh(["systemctl", "is-active", name], timeout=3) or "unknown"


def curl_ok(url: str, timeout: float = 2.5) -> bool:
    try:
        urllib.request.urlopen(url, timeout=timeout)
        return True
    except Exception:
        return False


def profiles_path() -> Path:
    for p in PROFILES_CANDIDATES:
        if p.is_file():
            return p
    return PROFILES


def load_profiles() -> list[dict[str, Any]]:
    path = profiles_path()
    if not path.is_file():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return list(data.get("profiles") or [])
    except Exception:
        return []


def save_profiles(profiles: list[dict[str, Any]]) -> None:
    path = profiles_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps({"profiles": profiles}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.chmod(tmp, 0o600)
    tmp.replace(path)
    if is_docker():
        sh(["docker", "compose", "-f", str(DOCKER_DIR / "docker-compose.yml"),
            "--env-file", str(DOCKER_DIR / ".env"), "restart", "relay"], timeout=60)
    else:
        sh(["systemctl", "restart", "tproxy-server"], timeout=30)


def web_link(host: str, secret: str) -> str:
    return "https://t.me/webproxy?" + urllib.parse.urlencode({"server": host, "secret": secret})


def tg_link(host: str, secret: str) -> str:
    return "tg://webproxy?" + urllib.parse.urlencode({"server": host, "secret": secret})


def text_status() -> str:
    host = hostname()
    relay, mp, caddy = svc("tproxy-server"), svc("mtproxy"), svc("caddy")
    hz = curl_ok(f"http://127.0.0.1:{admin_port()}/healthz")
    rz = curl_ok(f"http://127.0.0.1:{admin_port()}/readyz")
    mark = "🟢" if rz else ("🟡" if hz else "🔴")
    mode = "docker" if is_docker() else "native"
    return (
        f"<b>TgWebProxyR</b> · {mode}\n\n"
        f"{mark} <code>{host}</code>\n"
        f"relay <code>{relay}</code> · mtproxy <code>{mp}</code> · caddy <code>{caddy}</code>\n"
        f"healthz {'ok' if hz else 'fail'} · readyz {'ok' if rz else 'fail'}"
    )


def text_proxy() -> str:
    return (
        f"<b>Прокси WEB</b>\n\n"
        f"Hostname: <code>{hostname()}</code>\n"
        f"HTTPS: <code>{CFG.get('TWPR_PORT_HTTPS', '443')}</code>\n"
        f"Режим: <code>{'docker' if is_docker() else 'native'}</code>\n\n"
        f"Desktop ≥ 7.1.1 → Add proxy → WEB"
    )


def text_users() -> str:
    profiles = load_profiles()
    if not profiles:
        return "<b>Пользователи</b>\n\nПусто. Нажмите ➕"
    lines = ["<b>Пользователи</b>\n"]
    for p in profiles:
        sec = str(p.get("secret", ""))
        short = sec[:8] + "…" if len(sec) > 8 else sec
        lines.append(f"• <b>{p.get('name', '?')}</b> · <code>{short}</code>")
    lines.append(f"\nВсего: <b>{len(profiles)}</b>")
    return "\n".join(lines)


def text_links() -> str:
    host = hostname()
    profiles = load_profiles()
    if not profiles and secret_default():
        profiles = [{"name": "default", "secret": secret_default()}]
    if not profiles:
        return "<b>Ссылки</b>\n\nНет secret."
    parts = ["<b>Ссылки</b>\n"]
    for p in profiles:
        sec = p.get("secret", "")
        parts.append(f"<b>{p.get('name', 'user')}</b>")
        parts.append(f"<code>{tg_link(host, sec)}</code>")
        parts.append(f"<code>{web_link(host, sec)}</code>\n")
    return "\n".join(parts)


def text_traffic() -> str:
    profiles = load_profiles()
    lines = ["<b>Трафик</b>\n", f"Профилей: <b>{len(profiles)}</b>"]
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{admin_port()}/metrics", timeout=2.5) as resp:
            m = resp.read().decode("utf-8", errors="replace")
        keep = [ln for ln in m.splitlines() if ln and not ln.startswith("#") and "session" in ln.lower()][:20]
        if keep:
            lines.append("\n<pre>" + "\n".join(keep)[:1800] + "</pre>")
    except Exception:
        lines.append("\nМетрики relay пока недоступны с хоста.")
    return "\n".join(lines)


def text_avail() -> str:
    host = hostname()
    checks = []
    if host and host != "—":
        url = f"https://{host}/"
        try:
            urllib.request.urlopen(url, timeout=5)
            checks.append(f"🟢 {url}")
        except Exception as e:
            checks.append(f"🔴 {url}\n<code>{e}</code>")
    hz = curl_ok(f"http://127.0.0.1:{admin_port()}/healthz")
    rz = curl_ok(f"http://127.0.0.1:{admin_port()}/readyz")
    checks.append(("🟢" if hz else "🔴") + " healthz")
    checks.append(("🟢" if rz else "🔴") + " readyz")
    checks.append(("🟢" if "run" in svc("mtproxy") or svc("mtproxy") == "active" else "🔴") + " mtproxy")
    checks.append(("🟢" if "run" in svc("caddy") or svc("caddy") == "active" else "🔴") + " caddy")
    return "<b>Доступность</b>\n\n" + "\n".join(checks)


def do_backup() -> str:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    dest = BACKUP_DIR / f"twpr-{stamp}"
    dest.mkdir(parents=True)
    for src in (SETTINGS, BOT_ENV, profiles_path(), CONFIG, DOCKER_DIR / ".env", Path("/etc/caddy/Caddyfile")):
        if src.is_file():
            shutil.copy2(src, dest / src.name)
    (dest / "meta.json").write_text(json.dumps({"created_at": stamp, "hostname": hostname()}, indent=2) + "\n", encoding="utf-8")
    return str(dest)


def list_backups() -> list[Path]:
    if not BACKUP_DIR.is_dir():
        return []
    return sorted([p for p in BACKUP_DIR.iterdir() if p.is_dir()], reverse=True)


def text_backups() -> str:
    items = list_backups()[:12]
    if not items:
        return "<b>Бэкапы</b>\n\nПусто."
    return "<b>Бэкапы</b>\n\n" + "\n".join(f"• <code>{p.name}</code>" for p in items)


def text_settings() -> str:
    tok = TOKEN
    masked = (tok[:6] + "…" + tok[-4:]) if len(tok) > 12 else "—"
    return (
        f"<b>Настройки</b>\n\n"
        f"Token: <code>{masked}</code>\n"
        f"Admin: <code>{CFG.get('ALLOWED_CHAT_IDS', '')}</code>\n"
        f"<code>{BOT_ENV}</code>"
    )


def run_doctor() -> str:
    if is_docker():
        out = sh(
            ["docker", "compose", "-f", str(DOCKER_DIR / "docker-compose.yml"),
             "--env-file", str(DOCKER_DIR / ".env"), "ps"],
            timeout=15,
        )
        return f"<b>Doctor · docker</b>\n\n<pre>{out[-3000:]}</pre>"
    try:
        r = subprocess.run(["/opt/tgwebproxyr/tgwebproxyr.sh", "doctor"], capture_output=True, text=True, timeout=120)
        out = ((r.stdout or "") + (r.stderr or ""))[-3000:]
        return f"<b>Doctor</b>\n\n<pre>{out}</pre>"
    except Exception as e:
        return f"<b>Doctor</b>\n<code>{e}</code>"


def send_message(chat_id: int, text: str, reply_markup: dict[str, Any] | None = None) -> None:
    payload: dict[str, Any] = {
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True,
    }
    if reply_markup:
        payload["reply_markup"] = reply_markup
    api("sendMessage", payload, timeout=10)


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
        api("editMessageText", payload, timeout=10)
    except Exception:
        send_message(chat_id, text, reply_markup)


def answer_cb(cb_id: str, text: str = "") -> None:
    try:
        payload: dict[str, Any] = {"callback_query_id": cb_id}
        if text:
            payload["text"] = text
            payload["show_alert"] = False
        api("answerCallbackQuery", payload, timeout=5)
    except Exception:
        pass


def handle_callback(cq: dict[str, Any]) -> None:
    global CFG, TOKEN, ALLOWED
    CFG, TOKEN, ALLOWED = reload_cfg()

    data = cq.get("data") or ""
    msg = cq.get("message") or {}
    chat = (msg.get("chat") or {}).get("id")
    mid = msg.get("message_id")
    cb_id = cq.get("id")
    if chat is None:
        return
    answer_cb(cb_id)  # сразу — чтобы UI не «тупил»
    if not allowed(chat):
        send_message(chat, "⛔ Нет доступа.")
        return

    if data == "menu":
        edit_message(chat, mid, "<b>TgWebProxyR</b>\nВыберите раздел.", main_menu_kb())
        return

    if data == "backup_create":
        path = do_backup()
        edit_message(chat, mid, f"<b>Бэкап</b>\n<code>{path}</code>", back_kb())
        return

    if data == "user_add":
        sec = pysecrets.token_hex(16)
        profiles = load_profiles()
        name = f"user{int(time.time()) % 100000}"
        profiles.append({"name": name, "secret": sec, "backend": "127.0.0.1:2398", "carrier_mode": "https"})
        try:
            save_profiles(profiles)
            host = hostname()
            edit_message(
                chat,
                mid,
                f"<b>+ {name}</b>\n<code>{sec}</code>\n\n<code>{tg_link(host, sec)}</code>",
                back_kb(),
            )
        except Exception as e:
            edit_message(chat, mid, f"Ошибка: <code>{e}</code>", back_kb())
        return

    mapping = {
        "status": text_status,
        "proxy": text_proxy,
        "users": text_users,
        "links": text_links,
        "traffic": text_traffic,
        "avail": text_avail,
        "settings": text_settings,
        "doctor": run_doctor,
        "backups": text_backups,
    }
    if data in mapping:
        extra = back_kb()
        if data == "users":
            extra = kb([[("➕ Secret", "user_add")], [("⬅️ Меню", "menu")]])
        elif data == "backups":
            extra = kb([[("🆕 Создать", "backup_create")], [("⬅️ Меню", "menu")]])
        edit_message(chat, mid, mapping[data](), extra)


def handle_message(msg: dict[str, Any]) -> None:
    global CFG, TOKEN, ALLOWED
    CFG, TOKEN, ALLOWED = reload_cfg()

    chat = (msg.get("chat") or {}).get("id")
    text = (msg.get("text") or "").strip()
    if chat is None:
        return
    if not allowed(chat):
        send_message(chat, "⛔ Нет доступа. Пройдите setup на сервере ещё раз.")
        return

    if text.startswith(("/start", "/menu")):
        send_message(chat, "<b>TgWebProxyR</b>\nВыберите раздел.", main_menu_kb())
        return
    cmds = {
        "/help": ("Команды: /menu /status /links /users /traffic /backups /doctor", main_menu_kb()),
        "/status": (text_status, back_kb),
        "/links": (text_links, back_kb),
        "/users": (text_users, lambda: kb([[("➕ Secret", "user_add")], [("⬅️ Меню", "menu")]])),
        "/traffic": (text_traffic, back_kb),
        "/backups": (text_backups, lambda: kb([[("🆕 Создать", "backup_create")], [("⬅️ Меню", "menu")]])),
        "/doctor": (run_doctor, back_kb),
    }
    for prefix, val in cmds.items():
        if text.startswith(prefix):
            body, mk = val
            send_message(chat, body() if callable(body) else body, mk() if callable(mk) else mk)
            return
    send_message(chat, "Откройте /menu", main_menu_kb())


def main() -> None:
    global CFG, TOKEN, ALLOWED
    CFG, TOKEN, ALLOWED = reload_cfg()
    if not TOKEN:
        raise SystemExit("BOT_TOKEN не задан — tgwebproxyr bot setup")
    if not ALLOWED:
        raise SystemExit("ALLOWED_CHAT_IDS пуст — tgwebproxyr bot setup (token → /start)")

    try:
        api("deleteWebhook", {"drop_pending_updates": True}, timeout=10)
    except Exception:
        pass

    offset = 0
    print(f"twpr-bot up · admins={ALLOWED} · docker={is_docker()}", flush=True)
    while True:
        try:
            res = api(
                "getUpdates",
                {"timeout": 25, "offset": offset, "allowed_updates": ["message", "callback_query"]},
                timeout=35,
            )
            for upd in res.get("result") or []:
                offset = max(offset, int(upd["update_id"]) + 1)
                if "callback_query" in upd:
                    handle_callback(upd["callback_query"])
                elif "message" in upd:
                    handle_message(upd["message"])
        except Exception as e:
            print(f"poll: {e}", flush=True)
            time.sleep(1.5)


if __name__ == "__main__":
    main()
