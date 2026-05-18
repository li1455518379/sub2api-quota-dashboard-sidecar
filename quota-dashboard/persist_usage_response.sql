WITH payload AS (
    SELECT convert_from(decode(:'body_b64', 'base64'), 'UTF8')::jsonb AS doc
),
decoded AS (
    SELECT
        doc,
        CASE
            WHEN COALESCE(doc->>'code', '') ~ '^-?[0-9]+$'
            THEN (doc->>'code')::INTEGER
            ELSE -1
        END AS response_code
    FROM payload
),
parsed AS (
    SELECT
        response_code,
        NULLIF(doc->'data'->>'updated_at', '') AS updated_at,
        NULLIF(doc->'data'->'five_hour'->>'resets_at', '') AS five_reset_at,
        NULLIF(doc->'data'->'seven_day'->>'resets_at', '') AS seven_reset_at,
        CASE
            WHEN NULLIF(doc->'data'->'five_hour'->>'utilization', '') ~ '^[0-9]+(\.[0-9]+)?$'
            THEN NULLIF(doc->'data'->'five_hour'->>'utilization', '')::NUMERIC
        END AS five_used_percent,
        CASE
            WHEN NULLIF(doc->'data'->'seven_day'->>'utilization', '') ~ '^[0-9]+(\.[0-9]+)?$'
            THEN NULLIF(doc->'data'->'seven_day'->>'utilization', '')::NUMERIC
        END AS seven_used_percent,
        CASE
            WHEN NULLIF(doc->'data'->'five_hour'->>'remaining_seconds', '') ~ '^[0-9]+$'
            THEN NULLIF(doc->'data'->'five_hour'->>'remaining_seconds', '')::INTEGER
        END AS five_remaining_seconds,
        CASE
            WHEN NULLIF(doc->'data'->'seven_day'->>'remaining_seconds', '') ~ '^[0-9]+$'
            THEN NULLIF(doc->'data'->'seven_day'->>'remaining_seconds', '')::INTEGER
        END AS seven_remaining_seconds,
        regexp_replace(
            COALESCE(
                NULLIF(doc->'error'->>'message', ''),
                NULLIF(doc->>'message', ''),
                NULLIF(doc->>'msg', ''),
                CASE
                    WHEN response_code <> 0 THEN 'api_code_' || response_code::TEXT
                END,
                'invalid_usage_response'
            ),
            E'[\t\r\n]+',
            ' ',
            'g'
        ) AS refresh_error
    FROM decoded
),
prepared AS (
    SELECT
        response_code = 0 AS response_ok,
        updated_at,
        five_reset_at,
        seven_reset_at,
        five_used_percent,
        seven_used_percent,
        seven_used_percent AS primary_used_percent,
        five_used_percent AS secondary_used_percent,
        five_remaining_seconds,
        seven_remaining_seconds,
        response_code = 0 AND five_used_percent IS NOT NULL AS five_hour_success,
        response_code = 0 AND seven_used_percent IS NOT NULL AS seven_day_success,
        response_code = 0 AND seven_used_percent IS NOT NULL AS primary_success,
        response_code = 0 AND five_used_percent IS NOT NULL AS secondary_success,
        10080 AS primary_window_minutes,
        CASE
            WHEN five_reset_at IS NULL
             AND COALESCE(five_remaining_seconds, 0) = 0
             AND five_used_percent = 0
            THEN 0
            ELSE 300
        END AS secondary_window_minutes,
        refresh_error
    FROM parsed
),
updated AS (
    UPDATE accounts AS a
    SET extra = COALESCE(a.extra, '{}'::jsonb) || jsonb_build_object(
        'codex_usage_updated_at', p.updated_at,
        'codex_5h_used_percent', p.five_used_percent,
        'codex_7d_used_percent', p.seven_used_percent,
        'codex_primary_used_percent', p.primary_used_percent,
        'codex_secondary_used_percent', p.secondary_used_percent,
        'codex_5h_reset_at', p.five_reset_at,
        'codex_7d_reset_at', p.seven_reset_at,
        'codex_5h_reset_after_seconds', p.five_remaining_seconds,
        'codex_7d_reset_after_seconds', p.seven_remaining_seconds,
        'codex_primary_reset_after_seconds', p.seven_remaining_seconds,
        'codex_secondary_reset_after_seconds', p.five_remaining_seconds,
        'codex_5h_window_minutes', 300,
        'codex_7d_window_minutes', 10080,
        'codex_primary_window_minutes', p.primary_window_minutes,
        'codex_secondary_window_minutes', p.secondary_window_minutes
    )
    FROM prepared AS p
    WHERE a.id = (:'account_id')::BIGINT
      AND p.response_ok
    RETURNING 1
),
recorded AS (
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
    SELECT
        (:'account_id')::BIGINT,
        CASE
            WHEN response_ok AND seven_day_success THEN 'success'
            WHEN response_ok THEN 'partial'
            ELSE 'failed'
        END,
        CASE
            WHEN response_ok AND seven_day_success THEN NULL
            ELSE refresh_error
        END,
        updated_at,
        five_hour_success,
        seven_day_success,
        primary_success,
        secondary_success,
        now()
    FROM prepared
    ON CONFLICT (account_id) DO UPDATE SET
        refresh_status = EXCLUDED.refresh_status,
        refresh_error = EXCLUDED.refresh_error,
        usage_updated_at = EXCLUDED.usage_updated_at,
        five_hour_success = EXCLUDED.five_hour_success,
        seven_day_success = EXCLUDED.seven_day_success,
        primary_success = EXCLUDED.primary_success,
        secondary_success = EXCLUDED.secondary_success,
        refreshed_at = EXCLUDED.refreshed_at
    RETURNING 1
)
SELECT 1
FROM recorded;
