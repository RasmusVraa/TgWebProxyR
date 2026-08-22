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
CLI = Path(os.environ.get("TWPR_CLI", "/opt/tgwebproxyr/tgwebproxyr.sh"))
API = "https://api.telegram.org/bot{token}/{method}"
PER_PAGE = 8
# chat_id -> {"action": "add"|"rename", "old": str, "mid": int|None}
PENDING: dict[int, dict[str, Any]] = {}


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


def sh(cmd: list[str], timeout: float = 4, env: dict[str, str] | None = None) -> str:
    try:
        e = {**os.environ, **(env or {})}
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=e)
        return ((r.stdout or "") + (r.stderr or "")).strip()
    except Exception as e:
        return str(e)


def sanitize_name(raw: str) -> str:
    return "".join(c for c in raw.strip() if c.isalnum() or c in "._-")[:48]


def cli_secret(*args: str, timeout: float = 120) -> str:
    return sh([str(CLI), "secret", *args], timeout=timeout, env={"TWPR_YES": "1"})


def apply_profiles() -> str:
    return cli_secret("apply", timeout=100)


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
        rows.append([("✏️ Имя", f"u:ren:{name}"), ("🗑 Удалить", f"u:del:{name}")])
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


def _admin_base() -> str:
    port = CFG.get("TWPR_PORT_ADMIN") or "8081"
    return f"http://127.0.0.1:{port}"


def _http_get(url: str, timeout: float = 2.5) -> tuple[int, str]:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as r:
            return int(getattr(r, "status", 200) or 200), r.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        try:
            body = e.read().decode("utf-8", errors="replace")
        except Exception:
            body = ""
        return int(e.code), body
    except Exception:
        return 0, ""


def _fetch_metrics_docker() -> str:
    """Fallback: admin слушает loopback внутри контейнера — через compose exec."""
    compose = DOCKER_DIR / "docker-compose.yml"
    envf = DOCKER_DIR / ".env"
    if not compose.is_file() or not envf.is_file():
        return ""
    for svc in ("relay", "mtproxy"):
        out = sh(
            [
                "docker",
                "compose",
                "-f",
                str(compose),
                "--env-file",
                str(envf),
                "exec",
                "-T",
                svc,
                "curl",
                "-fsS",
                "--max-time",
                "3",
                "http://127.0.0.1:8081/metrics",
            ],
            timeout=8,
        )
        if out and "tproxy_" in out:
            return out
    return ""


def _fetch_metrics() -> str:
    code, body = _http_get(f"{_admin_base()}/metrics")
    if code == 200 and body.strip():
        return body
    # Docker: порт с хоста мог не проброситься на 127.0.0.1-bind
    if is_docker():
        via = _fetch_metrics_docker()
        if via:
            return via
    return body if code == 200 else ""


def _probe_admin() -> str:
    """ready | alive | down"""
    code, _ = _http_get(f"{_admin_base()}/readyz", timeout=2.0)
    if code == 200:
        return "ready"
    code, _ = _http_get(f"{_admin_base()}/healthz", timeout=2.0)
    if code == 200:
        return "alive"
    if is_docker() and _fetch_metrics_docker():
        return "ready"
    # docker healthz
    compose = DOCKER_DIR / "docker-compose.yml"
    envf = DOCKER_DIR / ".env"
    if compose.is_file() and envf.is_file():
        for path in ("readyz", "healthz"):
            out = sh(
                [
                    "docker",
                    "compose",
                    "-f",
                    str(compose),
                    "--env-file",
                    str(envf),
                    "exec",
                    "-T",
                    "mtproxy",
                    "curl",
                    "-fsS",
                    "--max-time",
                    "2",
                    f"http://127.0.0.1:8081/{path}",
                ],
                timeout=6,
            )
            if out.strip() or "ready" in out.lower() or "ok" in out.lower():
                return "ready" if path == "readyz" else "alive"
    return "down"


def _human_bytes(n: float) -> str:
    units = ["B", "KiB", "MiB", "GiB", "TiB"]
    v = float(n)
    i = 0
    while v >= 1024 and i < len(units) - 1:
        v /= 1024
        i += 1
    return f"{v:.1f} {units[i]}"


def text_traffic() -> str:
    users = load_profiles()
    raw = _fetch_metrics()
    probe = _probe_admin()
    lines = [
        "<b>Трафик</b>\n",
        f"Профилей: <b>{len(users)}</b>",
        f"Relay admin: <b>{esc(probe)}</b>",
    ]
    if not raw:
        lines.append("\nМетрики <code>/metrics</code> недоступны с хоста.")
        if probe in ("ready", "alive"):
            lines.append(
                "<i>health внутри Docker OK. Обновите ≥1.6.11 "
                "(admin-proxy) и <code>tgwebproxyr update</code>.</i>"
            )
        else:
            lines.append("<i>Проверьте: <code>tgwebproxyr health</code></i>")
        return "\n".join(lines)

    sessions = None
    streams = None
    bytes_up = None
    bytes_down = None
    extra: dict[str, float] = {}
    for ln in raw.splitlines():
        if not ln or ln.startswith("#"):
            continue
        parts = ln.split()
        if len(parts) < 2:
            continue
        key, val = parts[0], parts[-1]
        try:
            num = float(val)
        except ValueError:
            continue
        low = key.lower()
        if "sessions_live" in low or low.endswith("_sessions") or low == "tproxy_sessions_live":
            sessions = num
        elif "streams_live" in low:
            streams = num
        elif "bytes_up" in low:
            bytes_up = num
        elif "bytes_down" in low:
            bytes_down = num
        elif "byte" in low or "pending_bytes" in low:
            extra[key] = num

    if sessions is not None:
        lines.append(f"Сессии (live): <b>{int(sessions)}</b>")
    if streams is not None:
        lines.append(f"Потоки (live): <b>{int(streams)}</b>")
    if bytes_up is not None:
        lines.append(f"↑ up: <b>{_human_bytes(bytes_up)}</b>")
    if bytes_down is not None:
        lines.append(f"↓ down: <b>{_human_bytes(bytes_down)}</b>")
    if bytes_up is None and bytes_down is None and extra:
        lines.append("")
        for k in sorted(extra, key=lambda x: -extra[x])[:6]:
            lines.append(f"• <code>{esc(k)}</code>: <b>{_human_bytes(extra[k])}</b>")
    if sessions is None and bytes_up is None and not extra:
        snippet = "\n".join(ln for ln in raw.splitlines() if ln and not ln.startswith("#"))[:500]
        lines.append(f"\n<pre>{esc(snippet)}</pre>")

    lines.append("\n<i>Счётчики tproxy-server (глобальные).</i>")
    return "\n".join(lines)


AUTOBACKUP_ENV = STATE_DIR / "autobackup.env"


def load_autobackup() -> dict[str, str]:
    d = {"TWPR_AUTOBACKUP": "off", "TWPR_AUTOBACKUP_SEND": "1", "TWPR_AUTOBACKUP_KEEP": "12"}
    d.update(load_dotenv(AUTOBACKUP_ENV))
    return d


def save_autobackup(data: dict[str, str], apply_timer: bool = True) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    AUTOBACKUP_ENV.write_text(
        f"TWPR_AUTOBACKUP={data.get('TWPR_AUTOBACKUP', 'off')}\n"
        f"TWPR_AUTOBACKUP_SEND={data.get('TWPR_AUTOBACKUP_SEND', '1')}\n"
        f"TWPR_AUTOBACKUP_KEEP={data.get('TWPR_AUTOBACKUP_KEEP', '12')}\n",
        encoding="utf-8",
    )
    os.chmod(AUTOBACKUP_ENV, 0o600)
    if apply_timer:
        period = data.get("TWPR_AUTOBACKUP", "off")
        sh(["/opt/tgwebproxyr/tgwebproxyr.sh", "backup", "auto", period], timeout=20)
    else:
        # только флаг send — пересохранить через CLI send
        send = data.get("TWPR_AUTOBACKUP_SEND", "1")
        sh(
            ["/opt/tgwebproxyr/tgwebproxyr.sh", "backup", "auto", "send", "on" if send == "1" else "off"],
            timeout=15,
        )


def list_backup_files() -> list[Path]:
    if not BACKUP_DIR.is_dir():
        return []
    return sorted(BACKUP_DIR.glob("twpr-*.tar.gz"), key=lambda p: p.stat().st_mtime, reverse=True)


def text_backups() -> tuple[str, dict[str, Any]]:
    auto = load_autobackup()
    items = list_backup_files()[:10]
    period = auto.get("TWPR_AUTOBACKUP", "off")
    send = auto.get("TWPR_AUTOBACKUP_SEND", "1")
    lines = [
        "<b>Бэкапы</b>\n",
        f"Авто: <b>{esc(period)}</b> · в TG: <b>{'да' if send == '1' else 'нет'}</b>\n",
    ]
    if not items:
        lines.append("Архивов пока нет.")
    else:
        for p in items:
            kb_size = p.stat().st_size // 1024
            lines.append(f"• <code>{esc(p.name)}</code> · {kb_size}K")

    rows: list[list[tuple[str, str]]] = [
        [("🆕 Создать", "b:create"), ("⚙️ Авто", "b:auto")],
    ]
    # кнопки восстановления — по одному на архив (короткое имя)
    for i, p in enumerate(items[:6]):
        rows.append([(f"♻️ {p.name.replace('twpr-', '')[:22]}", f"b:ask:{i}")])
    rows.append([("⬅️ Меню", "m:root")])
    return "\n".join(lines), kb(rows)


def text_autobackup() -> tuple[str, dict[str, Any]]:
    auto = load_autobackup()
    period = auto.get("TWPR_AUTOBACKUP", "off")
    send = auto.get("TWPR_AUTOBACKUP_SEND", "1")
    body = (
        f"<b>Автобэкап</b>\n\n"
        f"Сейчас: <b>{esc(period)}</b>\n"
        f"Отправка файла админу: <b>{'вкл' if send == '1' else 'выкл'}</b>\n\n"
        f"При создании архив уходит в этот чат документом."
    )
    rows = [
        [("hourly", "b:auto:hourly"), ("daily", "b:auto:daily")],
        [("monthly", "b:auto:monthly"), ("off", "b:auto:off")],
        [("📤 TG " + ("выкл" if send == "1" else "вкл"), "b:auto:tg")],
        [("⬅️ К бэкапам", "m:backups")],
    ]
    return body, kb(rows)


def text_settings() -> str:
    tok = TOKEN
    masked = (tok[:6] + "…" + tok[-4:]) if len(tok) > 12 else "—"
    auto = load_autobackup()
    return (
        f"<b>Настройки</b>\n\n"
        f"Token: <code>{esc(masked)}</code>\n"
        f"Admin: <code>{esc(CFG.get('ALLOWED_CHAT_IDS', ''))}</code>\n"
        f"Hostname: <code>{esc(hostname())}</code>\n"
        f"default: <code>{'✓' if secret_default() else '—'}</code>\n"
        f"Автобэкап: <code>{esc(auto.get('TWPR_AUTOBACKUP', 'off'))}</code>\n"
        f"<code>{esc(BOT_ENV)}</code>"
    )


def do_backup() -> str:
    """Создаёт tar.gz через CLI (с отправкой в TG)."""
    out = sh(["/opt/tgwebproxyr/tgwebproxyr.sh", "backup", "create", "--quiet"], timeout=90)
    # последняя непустая строка — путь
    lines = [ln.strip() for ln in out.splitlines() if ln.strip()]
    path = lines[-1] if lines else ""
    if path.startswith("/") and Path(path).is_file():
        return path
    # fallback локально
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    dest = BACKUP_DIR / f"twpr-{stamp}"
    dest.mkdir(parents=True)
    for src in (SETTINGS, BOT_ENV, REGISTRY, AUTOBACKUP_ENV, DOCKER_DIR / ".env"):
        if src.is_file():
            shutil.copy2(src, dest / src.name)
    (dest / "meta.json").write_text(
        json.dumps({"created_at": stamp, "hostname": hostname()}, indent=2) + "\n",
        encoding="utf-8",
    )
    archive = BACKUP_DIR / f"twpr-{stamp}.tar.gz"
    sh(["tar", "-czf", str(archive), "-C", str(BACKUP_DIR), dest.name], timeout=30)
    shutil.rmtree(dest, ignore_errors=True)
    send_backup_document(archive)
    return str(archive)


def send_backup_document(archive: Path) -> None:
    if not archive.is_file() or not TOKEN:
        return
    for chat in ALLOWED:
        try:
            url = API.format(token=TOKEN, method="sendDocument")
            boundary = "----twpr" + pysecrets.token_hex(8)
            caption = f"💾 TgWebProxyR backup · {hostname()} · {archive.name}"
            body = bytearray()
            body.extend(
                (
                    f"--{boundary}\r\n"
                    f'Content-Disposition: form-data; name="chat_id"\r\n\r\n'
                    f"{chat}\r\n"
                    f"--{boundary}\r\n"
                    f'Content-Disposition: form-data; name="caption"\r\n\r\n'
                    f"{caption}\r\n"
                    f"--{boundary}\r\n"
                    f'Content-Disposition: form-data; name="document"; filename="{archive.name}"\r\n'
                    f"Content-Type: application/gzip\r\n\r\n"
                ).encode()
            )
            body.extend(archive.read_bytes())
            body.extend(f"\r\n--{boundary}--\r\n".encode())
            req = urllib.request.Request(
                url,
                data=bytes(body),
                headers={"Content-Type": f"multipart/form-data; boundary={boundary}"},
                method="POST",
            )
            urllib.request.urlopen(req, timeout=90)
        except Exception as e:
            print(f"sendDocument: {e}", flush=True)


def do_restore(name: str) -> str:
    out = sh(
        ["/opt/tgwebproxyr/tgwebproxyr.sh", "backup", "restore", name, "--yes"],
        timeout=120,
    )
    return out[-1500:] if out else "ok"


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

    if data == "u:add":
        PENDING[int(chat)] = {"action": "add", "mid": mid}
        show(
            chat,
            mid,
            "<b>Новый пользователь</b>\n\nОтправьте <b>имя</b> сообщением\n"
            "(латиница, цифры, <code>._-</code>).",
            kb([[("❌ Отмена", "u:list:0")]]),
        )
        return

    if data.startswith("u:ren:"):
        name = data.split(":", 2)[2]
        if name == "default":
            show(chat, mid, "default нельзя переименовать.", back_kb("u:list:0"))
            return
        PENDING[int(chat)] = {"action": "rename", "old": name, "mid": mid}
        show(
            chat,
            mid,
            f"<b>Переименовать</b> <code>{esc(name)}</code>\n\nОтправьте новое имя.",
            kb([[("❌ Отмена", f"u:show:{name}")]]),
        )
        return

    if data.startswith("u:show:"):
        PENDING.pop(int(chat), None)
        name = data.split(":", 2)[2]
        body, markup = text_user_card(name)
        show(chat, mid, body, markup)
        return

    if data.startswith("u:del:"):
        name = data.split(":", 2)[2]
        if name == "default":
            show(chat, mid, "default нельзя удалить — только rotate на сервере.", back_kb("u:list:0"))
            return
        out = cli_secret("remove", name)
        body, markup = text_users_page(0)
        show(chat, mid, f"Удалён <b>{esc(name)}</b>\n<pre>{esc(out[-400:])}</pre>\n\n" + body, markup)
        return

    if data.startswith("u:list:"):
        PENDING.pop(int(chat), None)
        page = int(data.split(":")[-1] or 0)
        body, markup = text_users_page(page)
        show(chat, mid, body, markup)
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
        show(chat, mid, text_traffic(), kb([[("🔃 Обновить", "m:traffic"), ("⬅️ Меню", "m:root")]]))
        return

    if data == "m:backups":
        body, markup = text_backups()
        show(chat, mid, body, markup)
        return

    if data == "b:create":
        show(chat, mid, "⏳ Собираю архив…", back_kb("m:backups"))
        path = do_backup()
        body, markup = text_backups()
        show(
            chat,
            mid,
            f"✅ Бэкап готов\n<code>{esc(Path(path).name if path else path)}</code>\n"
            f"<i>Файл отправлен в этот чат (если включена отправка).</i>\n\n{body}",
            markup,
        )
        return

    if data == "b:auto":
        body, markup = text_autobackup()
        show(chat, mid, body, markup)
        return

    if data.startswith("b:auto:"):
        action = data.split(":")[-1]
        auto = load_autobackup()
        if action in ("hourly", "daily", "monthly", "off"):
            auto["TWPR_AUTOBACKUP"] = action
            save_autobackup(auto)
        elif action == "tg":
            cur = auto.get("TWPR_AUTOBACKUP_SEND", "1")
            auto["TWPR_AUTOBACKUP_SEND"] = "0" if cur == "1" else "1"
            save_autobackup(auto, apply_timer=False)
        body, markup = text_autobackup()
        show(chat, mid, body, markup)
        return

    if data.startswith("b:ask:"):
        idx = int(data.split(":")[-1])
        items = list_backup_files()
        if idx < 0 or idx >= len(items):
            body, markup = text_backups()
            show(chat, mid, "Архив не найден.\n\n" + body, markup)
            return
        name = items[idx].name
        show(
            chat,
            mid,
            f"<b>Восстановить</b>\n<code>{esc(name)}</code>\n\n"
            f"Текущие настройки будут перезаписаны.",
            kb([[("✅ Да, восстановить", f"b:restore:{idx}"), ("❌ Отмена", "m:backups")]]),
        )
        return

    if data.startswith("b:restore:"):
        idx = int(data.split(":")[-1])
        items = list_backup_files()
        if idx < 0 or idx >= len(items):
            body, markup = text_backups()
            show(chat, mid, "Архив не найден.\n\n" + body, markup)
            return
        name = items[idx].name
        show(chat, mid, f"⏳ Восстанавливаю <code>{esc(name)}</code>…", back_kb("m:backups"))
        out = do_restore(name)
        body, markup = text_backups()
        show(
            chat,
            mid,
            f"✅ Восстановлено из <code>{esc(name)}</code>\n<pre>{esc(out[-800:])}</pre>\n\n{body}",
            markup,
        )
        return

    if data == "m:settings":
        show(chat, mid, text_settings(), kb([[("💾 Автобэкап", "b:auto"), ("⬅️ Меню", "m:root")]]))
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

    # ожидание имени (add / rename)
    pend = PENDING.get(int(chat))
    if pend and text and not text.startswith("/"):
        action = pend.get("action")
        mid = pend.get("mid")
        name = sanitize_name(text)
        if not name or name == "default":
            send_message(chat, "Некорректное имя. Попробуйте ещё раз или /users")
            return
        PENDING.pop(int(chat), None)
        if action == "add":
            send_message(chat, f"⏳ Создаю <b>{esc(name)}</b>…")
            out = cli_secret("add", name)
            p = next((x for x in load_profiles() if x.get("name") == name), None)
            if not p:
                send_message(chat, f"Не удалось создать.\n<pre>{esc(out[-500:])}</pre>", back_kb("u:list:0"))
                return
            sec = str(p.get("secret", ""))
            host = hostname()
            send_message(
                chat,
                f"<b>+ {esc(name)}</b>\n<code>{esc(sec)}</code>\n\n"
                f"<code>{esc(tg_link(host, sec))}</code>\n"
                f"<code>{esc(web_link(host, sec))}</code>",
                kb([[("👤 Карточка", f"u:show:{name}"), ("⬅️ Список", "u:list:0")]]),
            )
            return
        if action == "rename":
            old = str(pend.get("old") or "")
            send_message(chat, f"⏳ {esc(old)} → {esc(name)}…")
            out = cli_secret("rename", old, name)
            if not any(x.get("name") == name for x in load_profiles()):
                send_message(chat, f"Ошибка.\n<pre>{esc(out[-400:])}</pre>", back_kb("u:list:0"))
                return
            body, markup = text_user_card(name)
            send_message(chat, f"✅ Переименован\n\n{body}", markup)
            return

    if text.startswith(("/start", "/menu")):
        PENDING.pop(int(chat), None)
        send_message(chat, "<b>TgWebProxyR</b>\nВыберите раздел.", main_menu_kb())
        return

    mapping: dict[str, tuple[Any, Any]] = {
        "/status": (text_status, lambda: kb([[("🔃 Обновить", "m:status"), ("⬅️ Меню", "m:root")]])),
        "/proxy": (text_proxy, proxy_kb),
        "/users": (lambda: text_users_page(0)[0], lambda: text_users_page(0)[1]),
        "/links": (lambda: text_links_page(0)[0], lambda: text_links_page(0)[1]),
        "/logs": (text_logs, logs_kb),
        "/traffic": (text_traffic, lambda: kb([[("🔃 Обновить", "m:traffic"), ("⬅️ Меню", "m:root")]])),
        "/backups": (lambda: text_backups()[0], lambda: text_backups()[1]),
        "/help": (
            lambda: "Команды: /menu /status /proxy /users /links /logs /traffic /backups",
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
                    {"command": "traffic", "description": "Трафик"},
                    {"command": "backups", "description": "Бэкапы и автобэкап"},
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
