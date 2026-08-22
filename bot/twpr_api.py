#!/usr/bin/env python3
"""TgWebProxyR Shop API — для внешних магазинов / скриптов.

Auth: Authorization: Bearer <TWPR_API_TOKEN>
Listen: 127.0.0.1:8787 (по умолчанию)

Endpoints:
  GET  /v1/health
  GET  /v1/status
  GET  /v1/users
  POST /v1/users            {"name":"alice"}  → создаёт пользователя
  GET  /v1/users/{name}
  PATCH /v1/users/{name}    {"name":"bob"}    → переименовать
  DELETE /v1/users/{name}
  GET  /v1/users/{name}/link
  GET  /v1/traffic
"""
from __future__ import annotations

import json
import os
import secrets
import subprocess
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

STATE_DIR = Path(os.environ.get("TWPR_STATE_DIR", "/etc/tgwebproxyr"))
REGISTRY = STATE_DIR / "profiles.json"
SETTINGS = STATE_DIR / "settings.env"
API_ENV = STATE_DIR / "api.env"
DOCKER_DIR = Path("/opt/tgwebproxyr/docker")
HOST = os.environ.get("TWPR_API_HOST", "127.0.0.1")
PORT = int(os.environ.get("TWPR_API_PORT", "8787"))
CLI = "/opt/tgwebproxyr/tgwebproxyr.sh"


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


CFG = {**load_dotenv(SETTINGS), **load_dotenv(DOCKER_DIR / ".env"), **load_dotenv(API_ENV)}
TOKEN = CFG.get("TWPR_API_TOKEN") or os.environ.get("TWPR_API_TOKEN", "")


def hostname() -> str:
    return CFG.get("TWPR_HOSTNAME") or "—"


def secret_default() -> str:
    return CFG.get("TWPR_SECRET", "")


def load_profiles() -> list[dict[str, Any]]:
    if not REGISTRY.is_file():
        return []
    try:
        data = json.loads(REGISTRY.read_text(encoding="utf-8"))
        return list(data.get("profiles") or [])
    except Exception:
        return []


def ensure_default(profiles: list[dict[str, Any]]) -> list[dict[str, Any]]:
    sec = secret_default()
    rest = [p for p in profiles if p.get("name") != "default"]
    if sec:
        return [
            {"name": "default", "secret": sec, "backend": "127.0.0.1:2398", "carrier_mode": "https"}
        ] + rest
    return rest


def save_profiles(profiles: list[dict[str, Any]]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    profiles = ensure_default(profiles)
    tmp = REGISTRY.with_suffix(".tmp")
    tmp.write_text(json.dumps({"profiles": profiles}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.chmod(tmp, 0o600)
    tmp.replace(REGISTRY)
    # применить к движку
    subprocess.run([CLI, "secret", "apply"], capture_output=True, text=True, timeout=90)


def tg_link(host: str, secret: str) -> str:
    return "tg://webproxy?" + urllib.parse.urlencode({"server": host, "secret": secret})


def web_link(host: str, secret: str) -> str:
    return "https://t.me/webproxy?" + urllib.parse.urlencode({"server": host, "secret": secret})


def fetch_metrics() -> str:
    try:
        with urllib.request.urlopen("http://127.0.0.1:8081/metrics", timeout=2.5) as r:
            return r.read().decode("utf-8", errors="replace")
    except Exception:
        return ""


def _parse_prom_line(ln: str) -> tuple[str, dict[str, str], float] | None:
    ln = ln.strip()
    if not ln or ln.startswith("#"):
        return None
    parts = ln.rsplit(None, 1)
    if len(parts) != 2:
        return None
    left, val_s = parts
    try:
        val = float(val_s)
    except ValueError:
        return None
    labels: dict[str, str] = {}
    name = left
    if "{" in left and left.endswith("}"):
        name, rest = left.split("{", 1)
        rest = rest[:-1]
        for piece in rest.split(","):
            piece = piece.strip()
            if "=" not in piece:
                continue
            k, v = piece.split("=", 1)
            labels[k.strip()] = v.strip().strip('"')
    return name, labels, val


def parse_traffic(metrics: str) -> dict[str, Any]:
    """Глобальные + per-profile счётчики из /metrics."""
    out: dict[str, Any] = {
        "raw_lines": 0,
        "sessions": None,
        "bytes_up": None,
        "bytes_down": None,
        "users": [],
        "bytes": {},
    }
    if not metrics:
        return out
    lines = [ln for ln in metrics.splitlines() if ln and not ln.startswith("#")]
    out["raw_lines"] = len(lines)
    per: dict[str, dict[str, float]] = {}
    for ln in lines:
        parsed = _parse_prom_line(ln)
        if not parsed:
            continue
        name, labels, num = parsed
        low = name.lower()
        prof = labels.get("profile")
        if prof:
            slot = per.setdefault(prof, {"name": prof, "sessions": 0, "bytes_up": 0, "bytes_down": 0})
            if "sessions_live" in low:
                slot["sessions"] = num
            elif "bytes_up" in low:
                slot["bytes_up"] = num
            elif "bytes_down" in low:
                slot["bytes_down"] = num
            continue
        if low == "tproxy_sessions_live":
            out["sessions"] = num
        elif low == "tproxy_bytes_up_total":
            out["bytes_up"] = num
        elif low == "tproxy_bytes_down_total":
            out["bytes_down"] = num
        if "byte" in low:
            out["bytes"][name] = num
    out["users"] = sorted(per.values(), key=lambda u: str(u["name"]))
    return out


class Handler(BaseHTTPRequestHandler):
    server_version = "TgWebProxyR-API/1.0"

    def log_message(self, fmt: str, *args: Any) -> None:
        print(f"api: {self.address_string()} {fmt % args}", flush=True)

    def _json(self, code: int, obj: Any) -> None:
        body = json.dumps(obj, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_json(self) -> dict[str, Any]:
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0:
            return {}
        raw = self.rfile.read(n)
        try:
            return json.loads(raw.decode("utf-8"))
        except Exception:
            return {}

    def _auth(self) -> bool:
        if not TOKEN:
            self._json(503, {"error": "api token not configured — tgwebproxyr api setup"})
            return False
        auth = self.headers.get("Authorization") or ""
        got = ""
        if auth.lower().startswith("bearer "):
            got = auth[7:].strip()
        elif self.headers.get("X-Api-Token"):
            got = self.headers.get("X-Api-Token", "").strip()
        if not got or len(got) != len(TOKEN) or not secrets.compare_digest(got, TOKEN):
            self._json(401, {"error": "unauthorized"})
            return False
        return True

    def do_GET(self) -> None:  # noqa: N802
        path = urllib.parse.urlparse(self.path).path.rstrip("/") or "/"
        if path in ("/v1/health", "/health"):
            self._json(200, {"ok": True})
            return
        if not self._auth():
            return

        if path == "/v1/status":
            self._json(
                200,
                {
                    "hostname": hostname(),
                    "users": len(load_profiles()),
                    "mode": "docker" if (DOCKER_DIR / ".env").is_file() else "native",
                },
            )
            return

        if path == "/v1/users":
            users = []
            for p in load_profiles():
                users.append(
                    {
                        "name": p.get("name"),
                        "secret": p.get("secret"),
                        "link_tg": tg_link(hostname(), str(p.get("secret", ""))),
                        "link_https": web_link(hostname(), str(p.get("secret", ""))),
                    }
                )
            self._json(200, {"users": users})
            return

        if path == "/v1/traffic":
            m = fetch_metrics()
            self._json(200, {"hostname": hostname(), "metrics": parse_traffic(m), "snippet": m[-2000:]})
            return

        if path.startswith("/v1/users/"):
            rest = path[len("/v1/users/") :]
            if rest.endswith("/link"):
                name = rest[: -len("/link")]
                p = next((x for x in load_profiles() if x.get("name") == name), None)
                if not p:
                    self._json(404, {"error": "not found"})
                    return
                sec = str(p.get("secret", ""))
                self._json(
                    200,
                    {
                        "name": name,
                        "secret": sec,
                        "hostname": hostname(),
                        "tg": tg_link(hostname(), sec),
                        "https": web_link(hostname(), sec),
                    },
                )
                return
            name = rest
            p = next((x for x in load_profiles() if x.get("name") == name), None)
            if not p:
                self._json(404, {"error": "not found"})
                return
            sec = str(p.get("secret", ""))
            self._json(
                200,
                {
                    "name": name,
                    "secret": sec,
                    "tg": tg_link(hostname(), sec),
                    "https": web_link(hostname(), sec),
                },
            )
            return

        self._json(404, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        if not self._auth():
            return
        path = urllib.parse.urlparse(self.path).path.rstrip("/") or "/"
        if path != "/v1/users":
            self._json(404, {"error": "not found"})
            return
        body = self._read_json()
        name = str(body.get("name") or "").strip()
        name = "".join(c for c in name if c.isalnum() or c in "._-")
        if not name or name == "default":
            self._json(400, {"error": "invalid name"})
            return
        if any(p.get("name") == name for p in load_profiles()):
            self._json(409, {"error": "exists"})
            return
        try:
            # non-interactive add
            env = {**os.environ, "TWPR_YES": "1"}
            r = subprocess.run(
                [CLI, "secret", "add", name],
                capture_output=True,
                text=True,
                timeout=120,
                env=env,
                input="\n",
            )
            p = next((x for x in load_profiles() if x.get("name") == name), None)
            if not p:
                self._json(500, {"error": "create failed", "detail": (r.stderr or r.stdout)[-400:]})
                return
            sec = str(p.get("secret", ""))
            self._json(
                201,
                {
                    "name": name,
                    "secret": sec,
                    "tg": tg_link(hostname(), sec),
                    "https": web_link(hostname(), sec),
                },
            )
        except Exception as e:
            self._json(500, {"error": str(e)})

    def do_PATCH(self) -> None:  # noqa: N802
        if not self._auth():
            return
        path = urllib.parse.urlparse(self.path).path.rstrip("/") or "/"
        if not path.startswith("/v1/users/"):
            self._json(404, {"error": "not found"})
            return
        old = path[len("/v1/users/") :]
        body = self._read_json()
        new = str(body.get("name") or "").strip()
        new = "".join(c for c in new if c.isalnum() or c in "._-")
        if not new or old == "default":
            self._json(400, {"error": "invalid"})
            return
        r = subprocess.run(
            [CLI, "secret", "rename", old, new],
            capture_output=True,
            text=True,
            timeout=90,
            env={**os.environ, "TWPR_YES": "1"},
        )
        if r.returncode != 0:
            self._json(400, {"error": (r.stderr or r.stdout)[-300:]})
            return
        self._json(200, {"name": new, "renamed_from": old})

    def do_DELETE(self) -> None:  # noqa: N802
        if not self._auth():
            return
        path = urllib.parse.urlparse(self.path).path.rstrip("/") or "/"
        if not path.startswith("/v1/users/"):
            self._json(404, {"error": "not found"})
            return
        name = path[len("/v1/users/") :]
        if name == "default":
            self._json(400, {"error": "cannot delete default"})
            return
        r = subprocess.run(
            [CLI, "secret", "remove", name],
            capture_output=True,
            text=True,
            timeout=90,
            env={**os.environ, "TWPR_YES": "1"},
            input="y\n",
        )
        # remove may ask yn — with TWPR_YES should skip; ensure secrets.sh respects TWPR_YES
        if name in {p.get("name") for p in load_profiles()}:
            # force
            profiles = [p for p in load_profiles() if p.get("name") != name]
            save_profiles(profiles)
        self._json(200, {"deleted": name, "cli": (r.stdout or "")[-200:]})


def main() -> None:
    global TOKEN, CFG
    CFG = {**load_dotenv(SETTINGS), **load_dotenv(DOCKER_DIR / ".env"), **load_dotenv(API_ENV)}
    TOKEN = CFG.get("TWPR_API_TOKEN") or os.environ.get("TWPR_API_TOKEN", "")
    if not TOKEN:
        print("WARN: TWPR_API_TOKEN пуст — все запросы кроме /health вернут 503", flush=True)
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"twpr-api on http://{HOST}:{PORT}", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
