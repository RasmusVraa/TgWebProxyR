#!/usr/bin/env bash
# TgWebProxyR — лимиты трафика по пользователям
# Учёт в /etc/tgwebproxyr/usage.json; квота в profiles.json (quota_bytes, enabled).
# Enforce: enabled=false → профиль не попадает в relay/mtproxy (soft-disable).

TWPR_USAGE_FILE="${TWPR_USAGE_FILE:-${TWPR_STATE_DIR}/usage.json}"
TWPR_QUOTA_TIMER="/etc/systemd/system/tgwebproxyr-quota.timer"
TWPR_QUOTA_UNIT="/etc/systemd/system/tgwebproxyr-quota.service"

# 10G / 500M / 1024 → байты; unlimited|0|off → 0
TWPR_parse_bytes() {
  local raw="${1:-}" s n mul=1
  s="$(echo "$raw" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
  case "$s" in
    ""|unlimited|inf|none|off|-1) echo 0; return 0 ;;
  esac
  if [[ "$s" =~ ^([0-9]+)([kmgt])i?b?$ ]]; then
    n="${BASH_REMATCH[1]}"
    case "${BASH_REMATCH[2]}" in
      k) mul=1024 ;;
      m) mul=$((1024 * 1024)) ;;
      g) mul=$((1024 * 1024 * 1024)) ;;
      t) mul=$((1024 * 1024 * 1024 * 1024)) ;;
    esac
    echo $((n * mul))
    return 0
  fi
  if [[ "$s" =~ ^[0-9]+$ ]]; then
    echo "$s"
    return 0
  fi
  return 1
}

TWPR_quota_usage_init() {
  mkdir -p "$TWPR_STATE_DIR"
  if [[ ! -f "$TWPR_USAGE_FILE" ]]; then
    echo '{"users":{}}' >"$TWPR_USAGE_FILE"
    chmod 600 "$TWPR_USAGE_FILE"
  fi
}

# Снять снимок /metrics → обновить usage.json (без apply)
TWPR_quota_sync_usage() {
  TWPR_load_state 2>/dev/null || true
  TWPR_quota_usage_init
  command -v jq >/dev/null 2>&1 || return 1

  local admin="${TWPR_PORT_ADMIN:-8081}" body=""
  body="$(curl -fsS --max-time 3 "http://127.0.0.1:${admin}/metrics" 2>/dev/null)" || body=""
  if [[ -z "$body" ]] && TWPR_is_docker 2>/dev/null; then
    body="$(TWPR_docker_compose exec -T mtproxy \
      curl -fsS --max-time 3 http://127.0.0.1:8081/metrics 2>/dev/null)" || body=""
    [[ -z "$body" ]] && body="$(TWPR_docker_compose exec -T relay \
      curl -fsS --max-time 3 http://127.0.0.1:8081/metrics 2>/dev/null)" || body=""
  fi
  [[ -n "$body" ]] || return 1

  local snap tmp
  snap="$(mktemp)"
  tmp="$(mktemp)"
  printf '%s\n' "$body" | awk '
    index($1, "tproxy_bytes_up_total{") == 1 {
      split($1, a, "profile=\""); split(a[2], b, "\"");
      if (b[1] != "") up[b[1]] = $NF + 0
    }
    index($1, "tproxy_bytes_down_total{") == 1 {
      split($1, a, "profile=\""); split(a[2], b, "\"");
      if (b[1] != "") down[b[1]] = $NF + 0
    }
    END {
      for (n in up) print n "\t" up[n] "\t" (down[n] + 0)
      for (n in down) if (!(n in up)) print n "\t0\t" down[n]
    }
  ' >"$snap"

  # shellcheck disable=SC2016
  jq -n --slurpfile u "$TWPR_USAGE_FILE" --rawfile s "$snap" '
    ($u[0].users // {}) as $old
    | ($s | split("\n") | map(select(length>0) | split("\t")) ) as $rows
    | reduce $rows[] as $r ({users: $old};
        ($r[0]) as $name
        | ($r[1]|tonumber) as $up
        | ($r[2]|tonumber) as $down
        | (($up + $down)) as $cur
        | (($old[$name].last_up // 0) + ($old[$name].last_down // 0)) as $prev
        | (($old[$name].bytes_total // 0)) as $tot
        | (if $cur < $prev then $tot else ($tot + ($cur - $prev)) end) as $newt
        | .users[$name] = {
            bytes_total: $newt,
            last_up: $up,
            last_down: $down,
            updated_at: (now | floor)
          }
      )
  ' >"$tmp" 2>/dev/null || { rm -f "$snap" "$tmp"; return 1; }

  install -m 0600 "$tmp" "$TWPR_USAGE_FILE"
  rm -f "$snap" "$tmp"
  return 0
}

# Если used >= quota → enabled=false; вернуть число изменений
TWPR_quota_enforce() {
  TWPR_load_state 2>/dev/null || true
  [[ -f "$TWPR_REGISTRY" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 1
  TWPR_quota_sync_usage || true
  TWPR_quota_usage_init

  local tmp meta n hits
  tmp="$(mktemp)"
  meta="$(mktemp)"
  jq --slurpfile u "$TWPR_USAGE_FILE" '
    ($u[0].users // {}) as $usage
    | [
        (.profiles // [])[]
        | select(
            ((.quota_bytes // 0)|tonumber) > 0
            and ((($usage[.name].bytes_total // 0)|tonumber) >= ((.quota_bytes // 0)|tonumber))
            and ((.enabled // true) != false)
          )
        | .name
      ] as $hits
    | {
        profiles: (
          (.profiles // [])
          | map(
              if ((.quota_bytes // 0)|tonumber) > 0
                 and ((($usage[.name].bytes_total // 0)|tonumber) >= ((.quota_bytes // 0)|tonumber))
              then .enabled = false else . end
            )
        ),
        changed: ($hits|length),
        hits: $hits
      }
  ' "$TWPR_REGISTRY" >"$meta" 2>/dev/null || { rm -f "$tmp" "$meta"; return 1; }

  n="$(jq -r '.changed // 0' "$meta" 2>/dev/null || echo 0)"
  jq '{profiles: .profiles}' "$meta" >"$tmp"
  if [[ "${n:-0}" -gt 0 ]]; then
    install -m 0600 "$tmp" "$TWPR_REGISTRY"
    hits="$(jq -r '.hits // [] | join(", ")' "$meta" 2>/dev/null || true)"
    rm -f "$tmp" "$meta"
    TWPR_warn "Квота исчерпана — отключены: ${hits}"
    TWPR_profiles_apply_engine
    return 0
  fi
  rm -f "$tmp" "$meta"
  return 0
}

TWPR_quota_install_timer() {
  cat >"$TWPR_QUOTA_UNIT" <<'EOF'
[Unit]
Description=TgWebProxyR traffic quota check
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/tgwebproxyr quota check
Nice=10
EOF
  cat >"$TWPR_QUOTA_TIMER" <<'EOF'
[Unit]
Description=TgWebProxyR traffic quota timer

[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
AccuracySec=30s
Persistent=true

[Install]
WantedBy=timers.target
EOF
  chmod 0644 "$TWPR_QUOTA_UNIT" "$TWPR_QUOTA_TIMER"
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable --now tgwebproxyr-quota.timer 2>/dev/null || true
}

TWPR_cmd_quota() {
  local sub="${1:-check}"
  shift || true
  case "$sub" in
    check|sync)
      TWPR_require_root
      TWPR_quota_sync_usage || TWPR_warn "metrics недоступны — usage не обновлён"
      TWPR_quota_enforce
      TWPR_quota_install_timer 2>/dev/null || true
      TWPR_ok "квоты проверены"
      ;;
    status|show)
      TWPR_load_state
      TWPR_quota_usage_init
      TWPR_quota_sync_usage 2>/dev/null || true
      echo ""
      echo -e "  ${C_BOLD}Квоты трафика${C_RESET}"
      echo -e "  ${C_GRAY}────────────────────────────────────────${C_RESET}"
      if [[ -f "$TWPR_REGISTRY" ]] && command -v jq >/dev/null 2>&1; then
        jq -r --slurpfile u "$TWPR_USAGE_FILE" '
          ($u[0].users // {}) as $usage
          | .profiles[]?
          | . as $p
          | (($p.quota_bytes // 0)|tonumber) as $q
          | (($usage[$p.name].bytes_total // 0)|tonumber) as $used
          | (if ($p.enabled // true) == false then "OFF" else "ON" end) as $st
          | (if $q == 0 then "∞" else ($q|tostring) end) as $ql
          | "  \($p.name)\t\($st)\tused=\($used)\tquota=\($ql)"
        ' "$TWPR_REGISTRY" 2>/dev/null || true
      fi
      ;;
    timer|install-timer)
      TWPR_require_root
      TWPR_quota_install_timer
      TWPR_ok "таймер квот включён (каждую минуту)"
      ;;
    *)
      echo "  tgwebproxyr quota check|status|timer"
      ;;
  esac
}
