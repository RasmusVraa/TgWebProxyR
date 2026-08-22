#!/usr/bin/env python3
"""TgWebProxyR Shop API — для внешних магазинов / скриптов.

Auth: Authorization: Bearer <TWPR_API_TOKEN>
Listen: 127.0.0.1:8787 (по умолчанию)

Endpoints:
  GET  /v1/health
  GET  /v1/status
  GET  /v1/users
  POST /v1/users            {"name":"alice","quota_bytes":10737418240}  или "quota":"10G"
  GET  /v1/users/{name}
  PATCH /v1/users/{name}    {"name":"bob"} | {"quota_bytes":…} | {"quota":"10G"}
                            | {"enabled":true|false} | {"reset_usage":true}
  DELETE /v1/users/{name}
  GET  /v1/users/{name}/link
  GET  /v1/traffic
"""
from __future__ import annotations

import json
import os
import re
import secrets
import subprocess
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

STATE_DIR = Path(os.environ.get("TWPR_STATE_DIR", "/etc/tgwebproxyr"))
REGISTRY = STATE_DIR / "profiles.json"
USAGE_FILE = STATE_DIR / "usage.json"
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


def admin_port() -> str:
    return CFG.get("TWPR_PORT_ADMIN") or "8081"


def mtproxy_port() -> str:
    return CFG.get("TWPR_PORT_MTPROXY") or "2398"


def parse_bytes(raw: Any) -> int | None:
    if raw is None:
        return None
    if isinstance(raw, (int, float)):
        return max(0, int(raw))
    s = str(raw).strip().lower().replace(" ", "")
    if s in ("", "unlimited", "inf", "none", "off", "-1"):
        return 0
    m = re.fullmatch(r"(\d+)([kmgt])i?b?", s)
    if m:
        n = int(m.group(1))
        mul = {"k": 1024, "m": 1024**2, "g": 1024**3, "t": 1024**4}[m.group(2)]
        return n * mul
    if s.isdigit():
        return int(s)
    return None


def load_profiles() -> list[dict[str, Any]]:
    if not REGISTRY.is_file():
        return []
    try:
        data = json.loads(REGISTRY.read_text(encoding="utf-8"))
        return list(data.get("profiles") or [])
    except Exception:
        return []


def load_usage() -> dict[str, Any]:
    if not USAGE_FILE.is_file():
        return {}
    try:
        return dict(json.loads(USAGE_FILE.read_text(encoding="utf-8")).get("users") or {})
    except Exception:
        return {}


def ensure_default(profiles: list[dict[str, Any]]) -> list[dict[str, Any]]:
    sec = secret_default()
    old = next((p for p in profiles if p.get("name") == "default"), {})
    rest = [p for p in profiles if p.get("name") != "default"]
    if sec:
        return [
            {
                "name": "default",
                "secret": sec,
                "backend": f"127.0.0.1:{mtproxy_port()}",
                "carrier_mode": "https",
                "enabled": old.get("enabled", True) if isinstance(old, dict) else True,
                "quota_bytes": int(old.get("quota_bytes") or 0) if isinstance(old, dict) else 0,
            }
        ] + rest
    return rest


def save_profiles(profiles: list[dict[str, Any]]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    profiles = ensure_default(profiles)
    tmp = REGISTRY.with_suffix(".tmp")
    tmp.write_text(json.dumps({"profiles": profiles}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.chmod(tmp, 0o600)
    tmp.replace(REGISTRY)
    subprocess.run([CLI, "secret", "apply"], capture_output=True, text=True, timeout=90)


def user_public(p: dict[str, Any]) -> dict[str, Any]:
    name = str(p.get("name", ""))
    sec = str(p.get("secret", ""))
    quota = int(p.get("quota_bytes") or 0)
    used = int((load_usage().get(name) or {}).get("bytes_total") or 0)
    enabled = p.get("enabled", True) is not False
    remaining = None if quota <= 0 else max(0, quota - used)
    return {
        "name": name,
        "secret": sec,
        "enabled": enabled,
        "quota_bytes": quota,
        "used_bytes": used,
        "remaining_bytes": remaining,
        "link_tg": tg_link(hostname(), sec),
        "link_https": web_link(hostname(), sec),
        "tg": tg_link(hostname(), sec),
        "https": web_link(hostname(), sec),
    }


def tg_link(host: str, secret: str) -> str:
    return "tg://webproxy?" + urllib.parse.urlencode({"server": host, "secret": secret})


def web_link(host: str, secret: str) -> str:
    return "https://t.me/webproxy?" + urllib.parse.urlencode({"server": host, "secret": secret})


def fetch_metrics() -> str:
    try:
        with urllib.request.urlopen(f"http://127.0.0.1:{admin_port()}/metrics", timeout=2.5) as r:
            return r.read().decode("utf-8", errors="replace")
    except Exception:
        pass
    # Docker fallback
    if (DOCKER_DIR / ".env").is_file():
        try:
            r = subprocess.run(
                [
                    "docker",
                    "compose",
                    "-f",
                    str(DOCKER_DIR / "docker-compose.yml"),
                    "--env-file",
                    str(DOCKER_DIR / ".env"),
                    "exec",
                    "-T",
                    "mtproxy",
                    "curl",
                    "-fsS",
                    "--max-time",
                    "3",
                    "http://127.0.0.1:8081/metrics",
                ],
                capture_output=True,
                text=True,
                timeout=8,
            )
            if r.returncode == 0 and r.stdout:
                return r.stdout
        except Exception:
            pass
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
    usage = load_usage()
    profiles = {str(p.get("name")): p for p in load_profiles()}
    names = list(profiles.keys())
    for n in per:
        if n not in names:
            names.append(n)
    users_out = []
    for n in names:
        p = profiles.get(n) or {"name": n}
        slot = per.get(n) or {}
        quota = int(p.get("quota_bytes") or 0)
        used = int((usage.get(n) or {}).get("bytes_total") or 0)
        users_out.append(
            {
                "name": n,
                "sessions": slot.get("sessions", 0),
                "bytes_up": slot.get("bytes_up", 0),
                "bytes_down": slot.get("bytes_down", 0),
                "enabled": p.get("enabled", True) is not False,
                "quota_bytes": quota,
                "used_bytes": used,
                "remaining_bytes": None if quota <= 0 else max(0, quota - used),
            }
        )
    out["users"] = users_out
    return out


def cli(*args: str, timeout: float = 120) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [CLI, *args],
        capture_output=True,
        text=True,
        timeout=timeout,
        env={**os.environ, "TWPR_YES": "1"},
        input="\n",
    )


class Handler(BaseHTTPRequestHandler):
    server_version = "TgWebProxyR-API/1.1"

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
            mode = CFG.get("TWPR_DEPLOY_MODE") or (
                "docker" if (DOCKER_DIR / ".env").is_file() else "native"
            )
            self._json(
                200,
                {"hostname": hostname(), "users": len(load_profiles()), "mode": mode},
            )
            return

        if path == "/v1/users":
            self._json(200, {"users": [user_public(p) for p in load_profiles()]})
            return

        if path == "/v1/traffic":
            cli("quota", "check", timeout=90)
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
                pub = user_public(p)
                self._json(
                    200,
                    {
                        "name": name,
                        "secret": pub["secret"],
                        "hostname": hostname(),
                        "tg": pub["tg"],
                        "https": pub["https"],
                    },
                )
                return
            p = next((x for x in load_profiles() if x.get("name") == rest), None)
            if not p:
                self._json(404, {"error": "not found"})
                return
            self._json(200, user_public(p))
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
            r = cli("secret", "add", name)
            p = next((x for x in load_profiles() if x.get("name") == name), None)
            if not p:
                self._json(500, {"error": "create failed", "detail": (r.stderr or r.stdout)[-400:]})
                return
            qb = parse_bytes(body.get("quota_bytes", body.get("quota")))
            if qb is not None:
                cli("secret", "quota", name, str(qb))
                p = next((x for x in load_profiles() if x.get("name") == name), p)
            self._json(201, user_public(p))
        except Exception as e:
            self._json(500, {"error": str(e)})

    def do_PATCH(self) -> None:  # noqa: N802
        if not self._auth():
            return
        path = urllib.parse.urlparse(self.path).path.rstrip("/") or "/"
        if not path.startswith("/v1/users/"):
            self._json(404, {"error": "not found"})
            return
        name = path[len("/v1/users/") :]
        body = self._read_json()
        p = next((x for x in load_profiles() if x.get("name") == name), None)
        if not p:
            self._json(404, {"error": "not found"})
            return

        if body.get("reset_usage") is True:
            cli("secret", "reset-usage", name)

        if "enabled" in body:
            if body.get("enabled") is False or str(body.get("enabled")).lower() in ("0", "false", "off"):
                cli("secret", "disable", name)
            else:
                cli("secret", "enable", name)

        qb = parse_bytes(body.get("quota_bytes", body.get("quota"))) if (
            "quota_bytes" in body or "quota" in body
        ) else None
        if qb is not None:
            cli("secret", "quota", name, str(qb))

        new = str(body.get("name") or "").strip()
        new = "".join(c for c in new if c.isalnum() or c in "._-")
        if new and new != name:
            if name == "default":
                self._json(400, {"error": "cannot rename default"})
                return
            r = cli("secret", "rename", name, new)
            if r.returncode != 0:
                self._json(400, {"error": (r.stderr or r.stdout)[-300:]})
                return
            name = new

        cli("quota", "check", timeout=90)
        p2 = next((x for x in load_profiles() if x.get("name") == name), None)
        if not p2:
            self._json(404, {"error": "not found after patch"})
            return
        self._json(200, user_public(p2))

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
        r = cli("secret", "remove", name)
        if name in {p.get("name") for p in load_profiles()}:
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
