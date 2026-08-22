#!/bin/sh
set -eu

HOSTNAME="${TWPR_HOSTNAME:?TWPR_HOSTNAME required}"
SECRET="${TWPR_SECRET:?TWPR_SECRET required}"
BACKEND="${TWPR_BACKEND:-mtproxy:2398}"
SITE_DIR="${TWPR_SITE_DIR:-/srv/tproxy-site}"
CFG_DIR="${TWPR_CFG_DIR:-/etc/tproxy-server}"

mkdir -p "$CFG_DIR"

cat >"${CFG_DIR}/config.json" <<EOF
{
  "public_hostname": "${HOSTNAME}",
  "listen": "0.0.0.0:8080",
  "admin_listen": "0.0.0.0:8081",
  "public_dir": "${SITE_DIR}",
  "profiles_file": "${CFG_DIR}/profiles.json",
  "enable_pprof": false,
  "limits": {
    "max_header_bytes": 16384,
    "max_body_bytes": 2097152,
    "max_frame_payload": 1048576,
    "carrier_batch_bytes": 2097152,
    "max_streams_per_session": 128,
    "max_closed_stream_ids": 4096,
    "max_pending_per_session": 33554432,
    "max_pending_global": 536870912,
    "max_pending_items_per_session": 16384,
    "max_pending_items_global": 262144,
    "max_sessions_per_ip": 0,
    "max_sessions_global": 128,
    "max_streams_global": 4096,
    "max_backend_dials_in_flight": 256,
    "new_sessions_per_minute": 600,
    "new_sessions_burst": 128,
    "new_streams_per_minute": 6000,
    "new_streams_burst": 512,
    "max_bootstraps_per_ip": 0,
    "max_bootstraps_global": 512,
    "new_bootstraps_per_minute": 1200,
    "new_bootstraps_burst": 256,
    "max_profiles": 32
  },
  "timeouts": {
    "backend_dial": "5s",
    "long_poll": "25s",
    "reconnect_grace": "2m",
    "bootstrap_lifetime": "2m",
    "read_header": "10s",
    "idle": "75s",
    "shutdown": "15s"
  }
}
EOF

# strip optional dd prefix for profile secret field
SECRET_HEX="$SECRET"
case "$SECRET_HEX" in
  dd????????????????????????????????) SECRET_HEX="${SECRET_HEX#dd}" ;;
esac

cat >"${CFG_DIR}/profiles.json" <<EOF
{
  "profiles": [
    {
      "name": "default",
      "secret": "${SECRET_HEX}",
      "backend": "${BACKEND}",
      "carrier_mode": "https"
    }
  ]
}
EOF

chmod 600 "${CFG_DIR}/profiles.json" "${CFG_DIR}/config.json" 2>/dev/null || true

exec /usr/local/bin/tproxy-server \
  -config "${CFG_DIR}/config.json" \
  -profiles-file "${CFG_DIR}/profiles.json"
