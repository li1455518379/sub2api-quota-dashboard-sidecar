CREATE TABLE IF NOT EXISTS custom_account_quota_latest (
    account_id BIGINT PRIMARY KEY,
    account_name TEXT NOT NULL,
    platform TEXT NOT NULL,
    account_type TEXT NOT NULL,
    status TEXT NOT NULL,
    schedulable BOOLEAN NOT NULL,
    last_used_at TIMESTAMPTZ,
    rate_limited_at TIMESTAMPTZ,
    rate_limit_reset_at TIMESTAMPTZ,
    usage_updated_at TEXT,
    codex_5h_used_percent NUMERIC,
    codex_7d_used_percent NUMERIC,
    codex_primary_used_percent NUMERIC,
    codex_secondary_used_percent NUMERIC,
    codex_5h_remaining_percent NUMERIC,
    codex_7d_remaining_percent NUMERIC,
    codex_primary_remaining_percent NUMERIC,
    codex_secondary_remaining_percent NUMERIC,
    codex_5h_reset_at TEXT,
    codex_7d_reset_at TEXT,
    codex_primary_reset_after_seconds INTEGER,
    codex_secondary_reset_after_seconds INTEGER,
    captured_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS custom_account_quota_summary_snapshots (
    id BIGSERIAL PRIMARY KEY,
    captured_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    total_accounts INTEGER NOT NULL,
    tracked_accounts INTEGER NOT NULL,
    tracked_5h_accounts INTEGER NOT NULL,
    tracked_7d_accounts INTEGER NOT NULL,
    avg_5h_remaining_pct NUMERIC,
    avg_7d_remaining_pct NUMERIC,
    avg_primary_remaining_pct NUMERIC,
    avg_secondary_remaining_pct NUMERIC,
    total_5h_equiv_accounts NUMERIC,
    total_7d_equiv_accounts NUMERIC,
    total_primary_equiv_accounts NUMERIC,
    total_secondary_equiv_accounts NUMERIC
);

CREATE TABLE IF NOT EXISTS custom_account_quota_refresh_latest (
    account_id BIGINT PRIMARY KEY,
    refresh_status TEXT NOT NULL DEFAULT 'failed',
    refresh_error TEXT,
    usage_updated_at TEXT,
    five_hour_success BOOLEAN NOT NULL DEFAULT FALSE,
    seven_day_success BOOLEAN NOT NULL DEFAULT FALSE,
    primary_success BOOLEAN NOT NULL DEFAULT FALSE,
    secondary_success BOOLEAN NOT NULL DEFAULT FALSE,
    refreshed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE IF EXISTS custom_account_quota_refresh_latest
    ADD COLUMN IF NOT EXISTS usage_updated_at TEXT;

ALTER TABLE IF EXISTS custom_account_quota_refresh_latest
    ADD COLUMN IF NOT EXISTS five_hour_success BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE IF EXISTS custom_account_quota_refresh_latest
    ADD COLUMN IF NOT EXISTS seven_day_success BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE IF EXISTS custom_account_quota_refresh_latest
    ADD COLUMN IF NOT EXISTS primary_success BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE IF EXISTS custom_account_quota_refresh_latest
    ADD COLUMN IF NOT EXISTS secondary_success BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE IF EXISTS custom_account_quota_refresh_latest
    ALTER COLUMN refresh_status SET DEFAULT 'failed';

ALTER TABLE IF EXISTS custom_account_quota_refresh_latest
    ALTER COLUMN refreshed_at SET DEFAULT now();

CREATE INDEX IF NOT EXISTS idx_custom_account_quota_latest_captured_at
    ON custom_account_quota_latest (captured_at DESC);

CREATE INDEX IF NOT EXISTS idx_custom_account_quota_summary_captured_at
    ON custom_account_quota_summary_snapshots (captured_at DESC);

CREATE INDEX IF NOT EXISTS idx_custom_account_quota_refresh_latest_refreshed_at
    ON custom_account_quota_refresh_latest (refreshed_at DESC);

CREATE TABLE IF NOT EXISTS custom_account_quota_health_snapshots (
    id BIGSERIAL PRIMARY KEY,
    captured_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    total_accounts INTEGER NOT NULL,
    active_accounts INTEGER NOT NULL DEFAULT 0,
    alive_accounts INTEGER NOT NULL DEFAULT 0,
    tracked_accounts INTEGER NOT NULL DEFAULT 0,
    schedulable_accounts INTEGER NOT NULL DEFAULT 0,
    schedulable_tracked_accounts INTEGER NOT NULL DEFAULT 0,
    tracked_5h_accounts INTEGER NOT NULL DEFAULT 0,
    tracked_7d_accounts INTEGER NOT NULL DEFAULT 0,
    schedulable_tracked_5h_accounts INTEGER NOT NULL DEFAULT 0,
    schedulable_tracked_7d_accounts INTEGER NOT NULL DEFAULT 0,
    healthy_accounts INTEGER NOT NULL DEFAULT 0,
    recovering_accounts INTEGER NOT NULL DEFAULT 0,
    quota_limited_accounts INTEGER NOT NULL DEFAULT 0,
    failed_accounts INTEGER NOT NULL DEFAULT 0,
    untracked_accounts INTEGER NOT NULL DEFAULT 0,
    disabled_accounts INTEGER NOT NULL DEFAULT 0,
    inactive_accounts INTEGER NOT NULL DEFAULT 0,
    refresh_success_accounts INTEGER NOT NULL DEFAULT 0,
    refresh_partial_accounts INTEGER NOT NULL DEFAULT 0,
    refresh_failed_accounts INTEGER NOT NULL DEFAULT 0,
    avg_all_5h_remaining_pct NUMERIC,
    avg_all_7d_remaining_pct NUMERIC,
    avg_5h_remaining_pct NUMERIC,
    avg_7d_remaining_pct NUMERIC,
    total_all_5h_equiv_accounts NUMERIC,
    total_all_7d_equiv_accounts NUMERIC,
    total_5h_equiv_accounts NUMERIC,
    total_7d_equiv_accounts NUMERIC
);

CREATE INDEX IF NOT EXISTS idx_custom_account_quota_health_snapshots_captured_at
    ON custom_account_quota_health_snapshots (captured_at DESC);
