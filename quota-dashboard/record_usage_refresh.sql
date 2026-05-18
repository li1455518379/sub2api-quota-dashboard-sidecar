INSERT INTO custom_account_quota_refresh_latest (
    account_id,
    refresh_status,
    refresh_error,
    usage_updated_at,
    five_hour_success,
    seven_day_success,
    primary_success,
    secondary_success,
    refreshed_at
)
VALUES (
    (:'account_id')::BIGINT,
    COALESCE(NULLIF(:'refresh_status', ''), 'failed'),
    NULLIF(:'refresh_error', ''),
    NULLIF(:'usage_updated_at', ''),
    COALESCE(NULLIF(:'five_hour_success', '')::BOOLEAN, FALSE),
    COALESCE(NULLIF(:'seven_day_success', '')::BOOLEAN, FALSE),
    COALESCE(NULLIF(:'primary_success', '')::BOOLEAN, FALSE),
    COALESCE(NULLIF(:'secondary_success', '')::BOOLEAN, FALSE),
    now()
)
ON CONFLICT (account_id) DO UPDATE SET
    refresh_status = EXCLUDED.refresh_status,
    refresh_error = EXCLUDED.refresh_error,
    usage_updated_at = EXCLUDED.usage_updated_at,
    five_hour_success = EXCLUDED.five_hour_success,
    seven_day_success = EXCLUDED.seven_day_success,
    primary_success = EXCLUDED.primary_success,
    secondary_success = EXCLUDED.secondary_success,
    refreshed_at = EXCLUDED.refreshed_at;
