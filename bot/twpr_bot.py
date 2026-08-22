#!/usr/bin/env python3
"""TgWebProxyR Telegram bot — UX как у MTProxyL/ProxyL: быстрые экраны, страницы, логи."""
from __future__ import annotations

import html
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
REGISTRY = STATE_DIR / "profiles.json"  # единый реестр (default всегда первый)
BACKUP_DIR = Path(os.environ.get("TWPR_BACKUP_DIR", "/opt/tgwebproxyr/backups"))
DOCKER_DIR = Path("/opt/tgwebproxyr/docker")
API = "https://api.telegram.org/bot{token}/{method}"
PER_PAGE = 8


def esc(v: Any) -> str:
    return html.escape(str(v), quote=False)


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


def reload_cfg() -> tuple[dict[str, str], str, set[str]]:
    cfg = {**load_dotenv(SETTINGS), **load_dotenv(BOT_ENV)}
    if (DOCKER_DIR / ".env").is_file():
        denv = load_dotenv(DOCKER_DIR / ".env")
        for k in ("TWPR_HOSTNAME", "TWPR_SECRET", "TWPR_EMAIL"):
            cfg.setdefault(k, denv.get(k, ""))
    token = cfg.get("BOT_TOKEN", "")
    allowed = {x.strip() for x in cfg.get("ALLOWED_CHAT_IDS", "").split(",") if x.strip()}
    return cfg, token, allowed


CFG, TOKEN, ALLOWED = reload_cfg()


def is_docker() -> bool:
    return CFG.get("TWPR_DEPLOY_MODE") == "docker" or (DOCKER_DIR / ".env").is_file()


def hostname() -> str:
    return CFG.get("TWPR_HOSTNAME") or "—"


def secret_default() -> str:
    return CFG.get("TWPR_SECRET", "")


def api(method: str, payload: dict[str, Any] | None = None, timeout: float = 8) -> dict[str, Any]:
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
    return bool(ALLOWED) and str(chat_id) in ALLOWED


def kb(rows: list[list[tuple[str, str]]]) -> dict[str, Any]:
    return {"inline_keyboard": [[{"text": t, "callback_data": d} for t, d in row] for row in rows]}


def main_menu_kb() -> dict[str, Any]:
    return kb(
        [
            [("ℹ️ Статус", "m:status"), ("🚦 Прокси", "m:proxy")],
            [("👥 Пользователи", "u:list:0"), ("🔗 Ссылки", "l:list:0")],
            [("📜 Логи", "m:logs"), ("📊 Трафик", "m:traffic")],
            [("💾 Бэкапы", "m:backups"), ("⚙️ Настройки", "m:settings")],
        ]
    )


def back_kb(target: str = "m:root") -> dict[str, Any]:
    return kb([[("⬅️ Меню", target)]])


def sh(cmd: list[str], timeout: float = 4) -> str:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return ((r.stdout or "") + (r.stderr or "")).strip()
    except Exception as e:
        return str(e)


# ── профили (реестр на хосте, default всегда первый) ─────────────────────────

def ensure_default(profiles: list[dict[str, Any]] | None = None) -> list[dict[str, Any]]:
    profiles = list(profiles or [])
    sec = secret_default()
    rest = [p for p in profiles if p.get("name") != "default"]
    if sec:
        profiles = [
            {
                "name": "default",
                "secret": sec,
                "backend": "127.0.0.1:2398",
                "carrier_mode": "https",
            }
        ] + rest
    elif rest:
        profiles = rest
    else:
        profiles = []
    return profiles


def load_profiles() -> list[dict[str, Any]]:
    profiles: list[dict[str, Any]] = []
    if REGISTRY.is_file():
        try:
            data = json.loads(REGISTRY.read_text(encoding="utf-8"))
            profiles = list(data.get("profiles") or [])
        except Exception:
            profiles = []
    profiles = ensure_default(profiles)
    # синхронизируем файл, если default появился/обновился
    try:
        save_registry(profiles)
    except Exception:
        pass
    return profiles


def save_registry(profiles: list[dict[str, Any]]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    profiles = ensure_default(profiles)
    tmp = REGISTRY.with_suffix(".tmp")
    tmp.write_text(
        json.dumps({"profiles": profiles}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    os.chmod(tmp, 0o600)
    tmp.replace(REGISTRY)


def web_link(host: str, secret: str) -> str:
    return "https://t.me/webproxy?" + urllib.parse.urlencode({"server": host, "secret": secret})


def tg_link(host: str, secret: str) -> str:
    return "tg://webproxy?" + urllib.parse.urlencode({"server": host, "secret": secret})


# ── быстрый статус контейнеров (без health-probe) ────────────────────────────

def _compose(*args: str, timeout: float = 5) -> str:
    if not (DOCKER_DIR / ".env").is_file():
        return ""
    return sh(
        [
            "docker",
            "compose",
            "-f",
            str(DOCKER_DIR / "docker-compose.yml"),
            "--env-file",
            str(DOCKER_DIR / ".env"),
            *args,
        ],
        timeout=timeout,
    )


def svc_line(name: str) -> str:
    if is_docker():
        mapping = {"relay": "relay", "mtproxy": "mtproxy", "caddy": "caddy", "tproxy-server": "relay"}
        dname = mapping.get(name, name)
        out = _compose("ps", "--format", "{{.Name}} {{.Status}}", dname, timeout=4)
        line = out.splitlines()[0] if out else ""
        low = line.lower()
        if "up" in low or "running" in low:
            return "🟢 running" if "unhealthy" not in low else "🟡 unhealthy"
        if "exit" in low:
            return "🔴 exited"
        return f"⚪ {line or 'missing'}"
    st = sh(["systemctl", "is-active", name], timeout=2) or "missing"
    if st == "active":
        return "🟢 active"
    if st == "inactive":
        return "🟡 inactive"
    return f"🔴 {st}"


def proxy_running() -> bool:
    if is_docker():
        out = _compose("ps", "--format", "{{.Status}}", "relay", timeout=4).lower()
        return "up" in out or "running" in out
    return sh(["systemctl", "is-active", "tproxy-server"], timeout=2) == "active"


# ── экраны ───────────────────────────────────────────────────────────────────

def text_status() -> str:
    host = hostname()
    mode = "docker" if is_docker() else "native"
    return (
        f"<b>TgWebProxyR</b> · {esc(mode)}\n\n"
        f"<code>{esc(host)}</code>\n"
        f"relay {svc_line('relay')}\n"
        f"mtproxy {svc_line('mtproxy')}\n"
        f"caddy {svc_line('caddy')}\n\n"
        f"<i>Без health-probe — быстро. Логи: кнопка ниже в меню.</i>"
    )


def text_proxy() -> str:
    run = proxy_running()
    return (
        f"<b>Прокси WEB</b>\n\n"
        f"Состояние: <b>{'работает' if run else 'остановлен'}</b>\n"
        f"Hostname: <code>{esc(hostname())}</code>\n"
        f"Режим: <code>{'docker' if is_docker() else 'native'}</code>\n"
        f"Профиль: <code>default</code>\n\n"
        f"Desktop ≥ 7.1.1 → Add proxy → WEB"
    )


def proxy_kb() -> dict[str, Any]:
    run = proxy_running()
    rows: list[list[tuple[str, str]]] = []
    if run:
        rows.append([("🔄 Рестарт", "px:restart"), ("⏹ Стоп", "px:stop")])
    else:
        rows.append([("▶️ Старт", "px:start")])
    rows.append([("🔃 Обновить", "m:proxy"), ("⬅️ Меню", "m:root")])
    return kb(rows)


def text_users_page(page: int) -> tuple[str, dict[str, Any]]:
    users = load_profiles()
    total = len(users)
    pages = max(1, (total + PER_PAGE - 1) // PER_PAGE) if total else 1
    page = max(0, min(page, pages - 1))
    if not total:
        body = "<b>Пользователи</b>\n\nПока никого. ➕ добавит первого (кроме default)."
        return body, kb([[("➕ Добавить", "u:add")], [("⬅️ Меню", "m:root")]])

    chunk = users[page * PER_PAGE : (page + 1) * PER_PAGE]
    lines = [f"<b>Пользователи</b> · {total}", ""]
    for p in chunk:
        name = str(p.get("name", "?"))
        sec = str(p.get("secret", ""))
        short = (sec[:8] + "…") if len(sec) > 8 else sec
        mark = "★ " if name == "default" else "• "
        lines.append(f"{mark}<b>{esc(name)}</b> · <code>{esc(short)}</code>")

    rows: list[list[tuple[str, str]]] = []
    # кнопки профилей по 2
    pair: list[tuple[str, str]] = []
    for p in chunk:
        name = str(p.get("name", "?"))
        pair.append((f"{'★ ' if name == 'default' else ''}{name}"[:28], f"u:show:{name}"))
        if len(pair) == 2:
            rows.append(pair)
            pair = []
    if pair:
        rows.append(pair)

    nav: list[tuple[str, str]] = []
    if pages > 1:
        nav.append(("◀️", f"u:list:{(page - 1) % pages}"))
        nav.append((f"{page + 1}/{pages}", "noop"))
        nav.append(("▶️", f"u:list:{(page + 1) % pages}"))
        rows.append(nav)
    rows.append([("➕ Добавить", "u:add"), ("⬅️ Меню", "m:root")])
    return "\n".join(lines), kb(rows)


def text_user_card(name: str) -> tuple[str, dict[str, Any]]:
    users = load_profiles()
    p = next((x for x in users if x.get("name") == name), None)
    if not p:
        return f"Профиль <code>{esc(name)}</code> не найден.", back_kb("u:list:0")
    sec = str(p.get("secret", ""))
    host = hostname()
    body = (
        f"<b>Профиль · {esc(name)}</b>\n\n"
        f"Secret: <code>{esc(sec)}</code>\n\n"
        f"<code>{esc(tg_link(host, sec))}</code>\n"
        f"<code>{esc(web_link(host, sec))}</code>"
    )
    rows = [[("🔗 Ссылка", f"l:show:{name}")]]
    if name != "default":
        rows.append([("🗑 Удалить", f"u:del:{name}")])
    rows.append([("⬅️ К списку", "u:list:0")])
    return body, kb(rows)


def text_links_page(page: int) -> tuple[str, dict[str, Any]]:
    users = load_profiles()
    total = len(users)
    pages = max(1, (total + PER_PAGE - 1) // PER_PAGE) if total else 1
    page = max(0, min(page, pages - 1))
    if not total:
        return "<b>Ссылки</b>\n\nНет профилей.", back_kb()

    chunk = users[page * PER_PAGE : (page + 1) * PER_PAGE]
    host = hostname()
    parts = [f"<b>Ссылки</b> · стр. {page + 1}/{pages}", ""]
    for p in chunk:
        name = str(p.get("name", "?"))
        sec = str(p.get("secret", ""))
        star = "★ " if name == "default" else ""
        parts.append(f"<b>{star}{esc(name)}</b>")
        parts.append(f"<code>{esc(tg_link(host, sec))}</code>")
        parts.append(f"<code>{esc(web_link(host, sec))}</code>\n")

    rows: list[list[tuple[str, str]]] = []
    if pages > 1:
        rows.append(
            [
                ("◀️", f"l:list:{(page - 1) % pages}"),
                (f"{page + 1}/{pages}", "noop"),
                ("▶️", f"l:list:{(page + 1) % pages}"),
            ]
        )
    rows.append([("⬅️ Меню", "m:root")])
    return "\n".join(parts), kb(rows)


def text_logs() -> str:
    if is_docker():
        out = _compose("logs", "--tail=40", "relay", "mtproxy", "caddy", timeout=8)
    else:
        out = sh(
            ["journalctl", "-u", "tproxy-server", "-u", "mtproxy", "-u", "caddy", "-n", "40", "--no-pager"],
            timeout=6,
        )
    if not out:
        out = "(пусто)"
    # Telegram HTML <pre> лимит
    clip = out[-3500:]
    return f"<b>Логи</b>\n\n<pre>{esc(clip)}</pre>"


def logs_kb() -> dict[str, Any]:
    return kb([[("🔃 Обновить", "m:logs"), ("⬅️ Меню", "m:root")]])


def text_traffic() -> str:
    users = load_profiles()
    lines = [f"<b>Трафик</b>\n", f"Профилей: <b>{len(users)}</b>", f"default: <code>{'есть' if secret_default() else 'нет'}</code>"]
    return "\n".join(lines)


def text_backups() -> str:
    if not BACKUP_DIR.is_dir():
        return "<b>Бэкапы</b>\n\nПусто."
    items = sorted([p for p in BACKUP_DIR.iterdir() if p.is_dir()], reverse=True)[:12]
    if not items:
        return "<b>Бэкапы</b>\n\nПусто."
    return "<b>Бэкапы</b>\n\n" + "\n".join(f"• <code>{esc(p.name)}</code>" for p in items)


def backups_kb() -> dict[str, Any]:
    return kb([[("🆕 Создать", "b:create")], [("⬅️ Меню", "m:root")]])


def text_settings() -> str:
    tok = TOKEN
    masked = (tok[:6] + "…" + tok[-4:]) if len(tok) > 12 else "—"
    return (
        f"<b>Настройки</b>\n\n"
        f"Token: <code>{esc(masked)}</code>\n"
        f"Admin: <code>{esc(CFG.get('ALLOWED_CHAT_IDS', ''))}</code>\n"
        f"Hostname: <code>{esc(hostname())}</code>\n"
        f"Профиль default: <code>{'✓' if secret_default() else '—'}</code>\n"
        f"<code>{esc(BOT_ENV)}</code>"
    )


def do_backup() -> str:
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    dest = BACKUP_DIR / f"twpr-{stamp}"
    dest.mkdir(parents=True)
    for src in (SETTINGS, BOT_ENV, REGISTRY, DOCKER_DIR / ".env"):
        if src.is_file():
            shutil.copy2(src, dest / src.name)
    (dest / "meta.json").write_text(
        json.dumps({"created_at": stamp, "hostname": hostname()}, indent=2) + "\n",
        encoding="utf-8",
    )
    return str(dest)


def proxy_action(action: str) -> str:
    if is_docker():
        if action == "start":
            _compose("up", "-d", "--remove-orphans", timeout=60)
        elif action == "stop":
            _compose("stop", timeout=30)
        else:
            _compose("restart", timeout=45)
    else:
        units = ["mtproxy", "tproxy-server", "caddy"]
        if action == "start":
            sh(["systemctl", "start", *units], timeout=20)
        elif action == "stop":
            sh(["systemctl", "stop", "caddy", "tproxy-server", "mtproxy"], timeout=20)
        else:
            sh(["systemctl", "restart", *units], timeout=30)
    return action


# ── telegram IO ──────────────────────────────────────────────────────────────

def send_message(chat_id: int, text: str, reply_markup: dict[str, Any] | None = None) -> None:
    payload: dict[str, Any] = {
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True,
    }
    if reply_markup:
        payload["reply_markup"] = reply_markup
    api("sendMessage", payload, timeout=8)


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
        api("editMessageText", payload, timeout=8)
    except Exception as e:
        if "not modified" in str(e).lower():
            return
        send_message(chat_id, text, reply_markup)


def answer_cb(cb_id: str, text: str = "") -> None:
    try:
        payload: dict[str, Any] = {"callback_query_id": cb_id}
        if text:
            payload["text"] = text
        api("answerCallbackQuery", payload, timeout=3)
    except Exception:
        pass


def show(chat: int, mid: int | None, text: str, markup: dict[str, Any] | None) -> None:
    if mid is not None:
        edit_message(chat, mid, text, markup)
    else:
        send_message(chat, text, markup)


# ── handlers ─────────────────────────────────────────────────────────────────

def handle_callback(cq: dict[str, Any]) -> None:
    global CFG, TOKEN, ALLOWED
    data = cq.get("data") or ""
    msg = cq.get("message") or {}
    chat = (msg.get("chat") or {}).get("id")
    mid = msg.get("message_id")
    cb_id = cq.get("id")
    if chat is None:
        return

    # сразу ACK — иначе Telegram крутит «думает»
    answer_cb(cb_id)
    if data == "noop":
        return

    CFG, TOKEN, ALLOWED = reload_cfg()
    if not allowed(chat):
        send_message(chat, "⛔ Нет доступа.")
        return

    if data in ("m:root", "menu"):
        show(chat, mid, "<b>TgWebProxyR</b>\nВыберите раздел.", main_menu_kb())
        return

    if data == "m:status":
        show(chat, mid, text_status(), kb([[("🔃 Обновить", "m:status"), ("⬅️ Меню", "m:root")]]))
        return

    if data == "m:proxy":
        show(chat, mid, text_proxy(), proxy_kb())
        return

    if data.startswith("px:"):
        action = data.split(":", 1)[1]
        titles = {"start": "Запускаю…", "stop": "Останавливаю…", "restart": "Перезапускаю…"}
        show(chat, mid, f"<b>{titles.get(action, action)}</b>", back_kb("m:proxy"))
        try:
            proxy_action(action)
        except Exception as e:
            show(chat, mid, f"Ошибка: <code>{esc(e)}</code>", back_kb("m:proxy"))
            return
        show(chat, mid, text_proxy(), proxy_kb())
        return

    if data.startswith("u:list:"):
        page = int(data.split(":")[-1] or 0)
        body, markup = text_users_page(page)
        show(chat, mid, body, markup)
        return

    if data == "u:add":
        sec = pysecrets.token_hex(16)
        name = f"user{int(time.time()) % 100000}"
        profiles = load_profiles()
        if any(p.get("name") == name for p in profiles):
            name = f"user{pysecrets.token_hex(3)}"
        profiles.append(
            {"name": name, "secret": sec, "backend": "127.0.0.1:2398", "carrier_mode": "https"}
        )
        save_registry(profiles)
        host = hostname()
        note = ""
        if is_docker():
            note = "\n\n<i>В Docker движок сейчас принимает только default. Профиль сохранён в реестре.</i>"
        show(
            chat,
            mid,
            f"<b>+ {esc(name)}</b>\n<code>{esc(sec)}</code>\n\n"
            f"<code>{esc(tg_link(host, sec))}</code>{note}",
            kb([[("⬅️ К списку", "u:list:0")]]),
        )
        return

    if data.startswith("u:show:"):
        name = data.split(":", 2)[2]
        body, markup = text_user_card(name)
        show(chat, mid, body, markup)
        return

    if data.startswith("u:del:"):
        name = data.split(":", 2)[2]
        if name == "default":
            show(chat, mid, "default нельзя удалить — только rotate на сервере.", back_kb("u:list:0"))
            return
        profiles = [p for p in load_profiles() if p.get("name") != name]
        save_registry(profiles)
        body, markup = text_users_page(0)
        show(chat, mid, f"Удалён <b>{esc(name)}</b>\n\n" + body, markup)
        return

    if data.startswith("l:list:"):
        page = int(data.split(":")[-1] or 0)
        body, markup = text_links_page(page)
        show(chat, mid, body, markup)
        return

    if data.startswith("l:show:"):
        name = data.split(":", 2)[2]
        body, markup = text_user_card(name)
        show(chat, mid, body, markup)
        return

    if data == "m:logs":
        show(chat, mid, text_logs(), logs_kb())
        return

    if data == "m:traffic":
        show(chat, mid, text_traffic(), back_kb())
        return

    if data == "m:backups":
        show(chat, mid, text_backups(), backups_kb())
        return

    if data == "b:create":
        path = do_backup()
        show(chat, mid, f"<b>Бэкап</b>\n<code>{esc(path)}</code>", backups_kb())
        return

    if data == "m:settings":
        show(chat, mid, text_settings(), back_kb())
        return


def handle_message(msg: dict[str, Any]) -> None:
    global CFG, TOKEN, ALLOWED
    CFG, TOKEN, ALLOWED = reload_cfg()

    chat = (msg.get("chat") or {}).get("id")
    text = (msg.get("text") or "").strip()
    if chat is None:
        return
    if not allowed(chat):
        send_message(chat, "⛔ Нет доступа.")
        return

    if text.startswith(("/start", "/menu")):
        send_message(chat, "<b>TgWebProxyR</b>\nВыберите раздел.", main_menu_kb())
        return

    mapping: dict[str, tuple[Any, Any]] = {
        "/status": (text_status, lambda: kb([[("🔃 Обновить", "m:status"), ("⬅️ Меню", "m:root")]])),
        "/proxy": (text_proxy, proxy_kb),
        "/users": (lambda: text_users_page(0)[0], lambda: text_users_page(0)[1]),
        "/links": (lambda: text_links_page(0)[0], lambda: text_links_page(0)[1]),
        "/logs": (text_logs, logs_kb),
        "/help": (
            lambda: "Команды: /menu /status /proxy /users /links /logs /backups",
            main_menu_kb,
        ),
    }
    for prefix, (body, mk) in mapping.items():
        if text.startswith(prefix):
            b = body() if callable(body) else body
            m = mk() if callable(mk) else mk
            send_message(chat, b, m)
            return
    send_message(chat, "Откройте /menu", main_menu_kb())


def main() -> None:
    global CFG, TOKEN, ALLOWED
    CFG, TOKEN, ALLOWED = reload_cfg()
    if not TOKEN:
        raise SystemExit("BOT_TOKEN не задан — tgwebproxyr bot setup")
    if not ALLOWED:
        raise SystemExit("ALLOWED_CHAT_IDS пуст — tgwebproxyr bot setup")

    # зарегистрировать default сразу при старте
    load_profiles()

    try:
        api("deleteWebhook", {"drop_pending_updates": True}, timeout=8)
        api(
            "setMyCommands",
            {
                "commands": [
                    {"command": "menu", "description": "Главное меню"},
                    {"command": "status", "description": "Статус"},
                    {"command": "proxy", "description": "Управление прокси"},
                    {"command": "users", "description": "Пользователи"},
                    {"command": "links", "description": "Ссылки"},
                    {"command": "logs", "description": "Логи"},
                ]
            },
            timeout=8,
        )
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
            time.sleep(1.2)


if __name__ == "__main__":
    main()
