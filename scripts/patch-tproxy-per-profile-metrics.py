#!/usr/bin/env python3
"""Patch telegramdesktop/tproxy-server for per-profile Prometheus metrics.

Usage:
  python3 scripts/patch-tproxy-per-profile-metrics.py /path/to/tproxy-server
"""
from __future__ import annotations

import sys
from pathlib import Path

MARKER = "TWPR_PER_PROFILE_METRICS"


def patch_manager(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        print(f"  skip {path} (already patched)")
        return False

    needle_fields = "\tbytesDown           atomic.Uint64\n\tlimitHits           atomic.Uint64\n}"
    repl_fields = (
        "\tbytesDown           atomic.Uint64\n"
        "\tlimitHits           atomic.Uint64\n"
        f"\t// {MARKER}\n"
        "\tbytesUpByProfile    sync.Map // string -> *atomic.Uint64\n"
        "\tbytesDownByProfile  sync.Map\n"
        "}"
    )
    if needle_fields not in text:
        raise SystemExit(f"manager.go: struct fields not found in {path}")
    text = text.replace(needle_fields, repl_fields, 1)

    needle_on = (
        "\t\tonUp:   func(count int) { m.bytesUp.Add(uint64(count)) },\n"
        "\t\tonDown: func(count int) { m.bytesDown.Add(uint64(count)) },\n"
    )
    repl_on = (
        "\t\tonUp:   func(count int) { m.addProfileBytes(entry.profile.Name, true, uint64(count)) },\n"
        "\t\tonDown: func(count int) { m.addProfileBytes(entry.profile.Name, false, uint64(count)) },\n"
    )
    if needle_on not in text:
        raise SystemExit(f"manager.go: onUp/onDown not found in {path}")
    text = text.replace(needle_on, repl_on, 1)

    helper = f'''
// {MARKER}
func (m *Manager) addProfileBytes(profile string, up bool, n uint64) {{
	if n == 0 || profile == "" {{
		return
	}}
	if up {{
		m.bytesUp.Add(n)
	}} else {{
		m.bytesDown.Add(n)
	}}
	store := &m.bytesDownByProfile
	if up {{
		store = &m.bytesUpByProfile
	}}
	actual, _ := store.LoadOrStore(profile, &atomic.Uint64{{}})
	actual.(*atomic.Uint64).Add(n)
}}

// ProfileStat is exported for admin /metrics labels.
type ProfileStat struct {{
	Name         string
	SessionsLive int
	StreamsLive  int
	BytesUp      uint64
	BytesDown    uint64
}}

func (m *Manager) ProfileStats() []ProfileStat {{
	m.mu.Lock()
	sessions := make(map[string]int, len(m.sessionsPerProfile))
	for k, v := range m.sessionsPerProfile {{
		sessions[k] = v
	}}
	streams := make(map[string]int, len(m.streamsPerProfile))
	for k, v := range m.streamsPerProfile {{
		streams[k] = v
	}}
	profiles := append([]config.Profile(nil), m.config.Profiles...)
	m.mu.Unlock()

	out := make([]ProfileStat, 0, len(profiles))
	for _, p := range profiles {{
		st := ProfileStat{{
			Name:         p.Name,
			SessionsLive: sessions[p.Name],
			StreamsLive:  streams[p.Name],
		}}
		if v, ok := m.bytesUpByProfile.Load(p.Name); ok {{
			st.BytesUp = v.(*atomic.Uint64).Load()
		}}
		if v, ok := m.bytesDownByProfile.Load(p.Name); ok {{
			st.BytesDown = v.(*atomic.Uint64).Load()
		}}
		out = append(out, st)
	}}
	return out
}}
'''
    # append before end of file
    if not text.endswith("\n"):
        text += "\n"
    text += helper
    path.write_text(text, encoding="utf-8")
    print(f"  patched {path}")
    return True


def patch_server(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        print(f"  skip {path} (already patched)")
        return False

    old = '''func (s *Server) serveMetrics(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	metrics := s.manager.Metrics()
	capacity := s.manager.Capacity()
	w.Header().Set("Content-Type", "text/plain; version=0.0.4")
	_, _ = fmt.Fprintf(w,
		"tproxy_sessions_live %d\\n"+
			"tproxy_streams_live %d\\n"+
			"tproxy_backend_dials_in_flight %d\\n"+
			"tproxy_pending_bytes %d\\n"+
			"tproxy_pending_items %d\\n"+
			"tproxy_sessions_created_total %d\\n"+
			"tproxy_sessions_closed_total %d\\n"+
			"tproxy_streams_opened_total %d\\n"+
			"tproxy_streams_rejected_total %d\\n"+
			"tproxy_backend_dial_failures_total %d\\n"+
			"tproxy_bytes_up_total %d\\n"+
			"tproxy_bytes_down_total %d\\n"+
			"tproxy_limit_hits_total %d\\n",
		capacity.Sessions, capacity.Streams, capacity.BackendDialsInFlight,
		capacity.PendingBytes, capacity.PendingItems,
		metrics.SessionsCreated, metrics.SessionsClosed,
		metrics.StreamsOpened, metrics.StreamsRejected,
		metrics.BackendDialFailures, metrics.BytesUp, metrics.BytesDown,
		metrics.LimitHits)
}
'''
    new = f'''func (s *Server) serveMetrics(w http.ResponseWriter, r *http.Request) {{
	// {MARKER}
	if r.Method != http.MethodGet {{
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}}
	metrics := s.manager.Metrics()
	capacity := s.manager.Capacity()
	w.Header().Set("Content-Type", "text/plain; version=0.0.4")
	_, _ = fmt.Fprintf(w,
		"tproxy_sessions_live %d\\n"+
			"tproxy_streams_live %d\\n"+
			"tproxy_backend_dials_in_flight %d\\n"+
			"tproxy_pending_bytes %d\\n"+
			"tproxy_pending_items %d\\n"+
			"tproxy_sessions_created_total %d\\n"+
			"tproxy_sessions_closed_total %d\\n"+
			"tproxy_streams_opened_total %d\\n"+
			"tproxy_streams_rejected_total %d\\n"+
			"tproxy_backend_dial_failures_total %d\\n"+
			"tproxy_bytes_up_total %d\\n"+
			"tproxy_bytes_down_total %d\\n"+
			"tproxy_limit_hits_total %d\\n",
		capacity.Sessions, capacity.Streams, capacity.BackendDialsInFlight,
		capacity.PendingBytes, capacity.PendingItems,
		metrics.SessionsCreated, metrics.SessionsClosed,
		metrics.StreamsOpened, metrics.StreamsRejected,
		metrics.BackendDialFailures, metrics.BytesUp, metrics.BytesDown,
		metrics.LimitHits)
	for _, st := range s.manager.ProfileStats() {{
		name := twprMetricLabel(st.Name)
		_, _ = fmt.Fprintf(w,
			"tproxy_sessions_live{{profile=\\"%s\\"}} %d\\n"+
				"tproxy_streams_live{{profile=\\"%s\\"}} %d\\n"+
				"tproxy_bytes_up_total{{profile=\\"%s\\"}} %d\\n"+
				"tproxy_bytes_down_total{{profile=\\"%s\\"}} %d\\n",
			name, st.SessionsLive,
			name, st.StreamsLive,
			name, st.BytesUp,
			name, st.BytesDown)
	}}
}}

func twprMetricLabel(value string) string {{
	out := make([]rune, 0, len(value))
	for _, r := range value {{
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '_' || r == '-' || r == '.' {{
			out = append(out, r)
		}} else {{
			out = append(out, '_')
		}}
	}}
	if len(out) == 0 {{
		return "unknown"
	}}
	return string(out)
}}
'''
    if old not in text:
        raise SystemExit(f"server.go: serveMetrics block not found in {path}")
    text = text.replace(old, new, 1)
    path.write_text(text, encoding="utf-8")
    print(f"  patched {path}")
    return True


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    root = Path(sys.argv[1]).resolve()
    manager = root / "internal" / "session" / "manager.go"
    server = root / "internal" / "server" / "server.go"
    if not manager.is_file() or not server.is_file():
        print(f"not a tproxy-server tree: {root}", file=sys.stderr)
        return 1
    print(f"patching {root}")
    patch_manager(manager)
    patch_server(server)
    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
