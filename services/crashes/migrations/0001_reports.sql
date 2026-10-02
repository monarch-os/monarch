CREATE TABLE reports (
  id TEXT PRIMARY KEY,
  payload_hash TEXT NOT NULL,
  fingerprint TEXT NOT NULL,
  application TEXT NOT NULL,
  crash_date TEXT NOT NULL,
  signal TEXT NOT NULL,
  package_version TEXT NOT NULL,
  monarch_version TEXT NOT NULL,
  received_at TEXT NOT NULL,
  state TEXT NOT NULL CHECK (state IN ('pending', 'ready'))
);

CREATE INDEX reports_group ON reports(state, fingerprint, received_at);
CREATE INDEX reports_retention ON reports(received_at);

CREATE TABLE daily_budget (
  day TEXT PRIMARY KEY,
  used INTEGER NOT NULL
);
