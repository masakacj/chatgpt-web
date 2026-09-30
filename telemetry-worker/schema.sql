CREATE TABLE IF NOT EXISTS perf_samples (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  received_at INTEGER NOT NULL,
  install_id TEXT NOT NULL,
  session_id TEXT NOT NULL,
  debug_id TEXT NOT NULL DEFAULT '',
  script_version TEXT NOT NULL DEFAULT '',
  app_version TEXT NOT NULL DEFAULT '',
  gesture_version TEXT NOT NULL DEFAULT '',
  mode TEXT NOT NULL DEFAULT '',
  route_kind TEXT NOT NULL DEFAULT '',
  reason TEXT NOT NULL DEFAULT '',
  aggressive INTEGER NOT NULL DEFAULT 0,
  streaming INTEGER NOT NULL DEFAULT 0,
  phase_two INTEGER NOT NULL DEFAULT 0,
  uptime_ms REAL NOT NULL DEFAULT 0,
  mounted_turns INTEGER NOT NULL DEFAULT 0,
  observer_callbacks INTEGER NOT NULL DEFAULT 0,
  conversation_mutations INTEGER NOT NULL DEFAULT 0,
  sidebar_mutations INTEGER NOT NULL DEFAULT 0,
  turn_refreshes INTEGER NOT NULL DEFAULT 0,
  tool_nodes_processed INTEGER NOT NULL DEFAULT 0,
  tool_groups INTEGER NOT NULL DEFAULT 0,
  tool_collapsed INTEGER NOT NULL DEFAULT 0,
  loop_count INTEGER NOT NULL DEFAULT 0,
  loop_avg_ms REAL NOT NULL DEFAULT 0,
  loop_max_ms REAL NOT NULL DEFAULT 0,
  loop_gt50 INTEGER NOT NULL DEFAULT 0,
  loop_gt100 INTEGER NOT NULL DEFAULT 0,
  loop_gt250 INTEGER NOT NULL DEFAULT 0,
  raf_count INTEGER NOT NULL DEFAULT 0,
  raf_max_ms REAL NOT NULL DEFAULT 0,
  raf_gt50 INTEGER NOT NULL DEFAULT 0,
  raf_gt100 INTEGER NOT NULL DEFAULT 0,
  raf_gt250 INTEGER NOT NULL DEFAULT 0,
  conversation_observer_ms REAL NOT NULL DEFAULT 0,
  sidebar_observer_ms REAL NOT NULL DEFAULT 0,
  turn_scan_ms REAL NOT NULL DEFAULT 0,
  tool_process_ms REAL NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_perf_received_at
  ON perf_samples(received_at);
CREATE INDEX IF NOT EXISTS idx_perf_debug_id
  ON perf_samples(debug_id, received_at);
CREATE INDEX IF NOT EXISTS idx_perf_install_id
  ON perf_samples(install_id, received_at);
