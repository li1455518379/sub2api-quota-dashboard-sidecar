WITH source AS (
    SELECT
        id,
        name,
        platform,
        type,
        NULLIF(LOWER(credentials->>'plan_type'), '') AS plan_type,
        status,
        schedulable,
        last_used_at,
        rate_limited_at,
        rate_limit_reset_at,
        temp_unschedulable_until,
        temp_unschedulable_reason,
        overload_until,
        extra,
        extra->>'codex_usage_updated_at' AS usage_updated_at,
        extra->>'codex_5h_reset_at' AS raw_codex_5h_reset_at,
        extra->>'codex_7d_reset_at' AS raw_codex_7d_reset_at,
        CASE
            WHEN extra->>'codex_5h_used_percent' ~ '^[0-9]+(\.[0-9]+)?$'
            THEN (extra->>'codex_5h_used_percent')::NUMERIC
        END AS used_5h,
        CASE
            WHEN extra->>'codex_7d_used_percent' ~ '^[0-9]+(\.[0-9]+)?$'
            THEN (extra->>'codex_7d_used_percent')::NUMERIC
        END AS used_7d,
        CASE
            WHEN extra->>'codex_5h_reset_after_seconds' ~ '^[0-9]+$'
            THEN (extra->>'codex_5h_reset_after_seconds')::INTEGER
        END AS raw_reset_5h_after_seconds,
        CASE
            WHEN extra->>'codex_7d_reset_after_seconds' ~ '^[0-9]+$'
            THEN (extra->>'codex_7d_reset_after_seconds')::INTEGER
        END AS raw_reset_7d_after_seconds,
        CASE
            WHEN extra->>'codex_5h_window_minutes' ~ '^[0-9]+$'
            THEN (extra->>'codex_5h_window_minutes')::INTEGER
        END AS window_5h_minutes,
        CASE
            WHEN extra->>'codex_7d_window_minutes' ~ '^[0-9]+$'
            THEN (extra->>'codex_7d_window_minutes')::INTEGER
        END AS window_7d_minutes,
        CASE
            WHEN extra->>'codex_primary_used_percent' ~ '^[0-9]+(\.[0-9]+)?$'
            THEN (extra->>'codex_primary_used_percent')::NUMERIC
        END AS used_primary,
        CASE
            WHEN extra->>'codex_secondary_used_percent' ~ '^[0-9]+(\.[0-9]+)?$'
            THEN (extra->>'codex_secondary_used_percent')::NUMERIC
        END AS used_secondary,
        CASE
            WHEN extra->>'codex_primary_reset_after_seconds' ~ '^[0-9]+$'
            THEN (extra->>'codex_primary_reset_after_seconds')::INTEGER
        END AS raw_primary_reset_after_seconds,
        CASE
            WHEN extra->>'codex_secondary_reset_after_seconds' ~ '^[0-9]+$'
            THEN (extra->>'codex_secondary_reset_after_seconds')::INTEGER
        END AS raw_secondary_reset_after_seconds,
        CASE
            WHEN extra->>'codex_primary_window_minutes' ~ '^[0-9]+$'
            THEN (extra->>'codex_primary_window_minutes')::INTEGER
        END AS window_primary_minutes,
        CASE
            WHEN extra->>'codex_secondary_window_minutes' ~ '^[0-9]+$'
            THEN (extra->>'codex_secondary_window_minutes')::INTEGER
        END AS window_secondary_minutes
    FROM accounts
    WHERE deleted_at IS NULL
      AND platform = 'openai'
      AND type = 'oauth'
),
refresh_state AS (
    SELECT
        account_id,
        refresh_status,
        refresh_error,
        usage_updated_at AS refresh_usage_updated_at,
        five_hour_success,
        seven_day_success,
        primary_success,
        secondary_success,
        refreshed_at
    FROM custom_account_quota_refresh_latest
),
base AS (
    SELECT
        s.id,
        s.name,
        s.platform,
        s.type,
        COALESCE(s.plan_type, 'unknown') AS plan_type,
        s.status,
        s.schedulable,
        s.last_used_at,
        s.rate_limited_at,
        s.rate_limit_reset_at,
        s.temp_unschedulable_until,
        s.temp_unschedulable_reason,
        s.overload_until,
        CASE
            WHEN s.status <> 'active' THEN FALSE
            WHEN s.schedulable IS DISTINCT FROM TRUE THEN FALSE
            WHEN s.temp_unschedulable_until IS NOT NULL AND s.temp_unschedulable_until > now() THEN FALSE
            WHEN s.overload_until IS NOT NULL AND s.overload_until > now() THEN FALSE
            WHEN s.rate_limit_reset_at IS NOT NULL AND s.rate_limit_reset_at > now() THEN FALSE
            WHEN s.rate_limit_reset_at IS NULL AND s.rate_limited_at IS NOT NULL THEN FALSE
            ELSE TRUE
        END AS effective_schedulable,
        s.usage_updated_at,
        CASE
            WHEN s.usage_updated_at ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
            THEN s.usage_updated_at::timestamptz
        END AS usage_updated_at_ts,
        CASE
            WHEN r.account_id IS NOT NULL THEN COALESCE(r.refresh_status, 'unknown')
            WHEN s.used_5h IS NOT NULL OR s.used_7d IS NOT NULL OR s.used_primary IS NOT NULL OR s.used_secondary IS NOT NULL THEN 'cached'
            ELSE 'unknown'
        END AS quota_refresh_status,
        r.refresh_error AS quota_refresh_error,
        r.refresh_usage_updated_at,
        r.refreshed_at AS quota_refreshed_at,
        CASE
            WHEN r.account_id IS NOT NULL THEN COALESCE(r.five_hour_success, FALSE)
            ELSE s.used_5h IS NOT NULL
        END AS five_hour_success,
        CASE
            WHEN r.account_id IS NOT NULL THEN COALESCE(r.seven_day_success, FALSE)
            ELSE s.used_7d IS NOT NULL
        END AS seven_day_success,
        CASE
            WHEN r.account_id IS NOT NULL THEN COALESCE(r.primary_success, FALSE)
            ELSE s.used_primary IS NOT NULL
        END AS primary_success,
        CASE
            WHEN r.account_id IS NOT NULL THEN COALESCE(r.secondary_success, FALSE)
            ELSE s.used_secondary IS NOT NULL
        END AS secondary_success,
        CASE
            WHEN (CASE WHEN r.account_id IS NOT NULL THEN COALESCE(r.five_hour_success, FALSE) ELSE s.used_5h IS NOT NULL END)
             AND s.used_5h IS NOT NULL
            THEN ROUND(s.used_5h, 2)
        END AS codex_5h_used_percent,
        CASE
            WHEN (CASE WHEN r.account_id IS NOT NULL THEN COALESCE(r.seven_day_success, FALSE) ELSE s.used_7d IS NOT NULL END)
             AND s.used_7d IS NOT NULL
            THEN ROUND(s.used_7d, 2)
        END AS codex_7d_used_percent,
        CASE
            WHEN (CASE WHEN r.account_id IS NOT NULL THEN COALESCE(r.primary_success, FALSE) ELSE s.used_primary IS NOT NULL END)
             AND s.used_primary IS NOT NULL
            THEN ROUND(s.used_primary, 2)
        END AS codex_primary_used_percent,
        CASE
            WHEN (CASE WHEN r.account_id IS NOT NULL THEN COALESCE(r.secondary_success, FALSE) ELSE s.used_secondary IS NOT NULL END)
             AND s.used_secondary IS NOT NULL
            THEN ROUND(s.used_secondary, 2)
        END AS codex_secondary_used_percent,
        CASE
            WHEN (CASE WHEN r.account_id IS NOT NULL THEN COALESCE(r.five_hour_success, FALSE) ELSE s.used_5h IS NOT NULL END)
             AND s.used_5h IS NOT NULL
            THEN ROUND(GREATEST(0, LEAST(100, 100 - s.used_5h)), 2)
        END AS codex_5h_remaining_percent,
        CASE
            WHEN (CASE WHEN r.account_id IS NOT NULL THEN COALESCE(r.seven_day_success, FALSE) ELSE s.used_7d IS NOT NULL END)
             AND s.used_7d IS NOT NULL
            THEN ROUND(GREATEST(0, LEAST(100, 100 - s.used_7d)), 2)
        END AS codex_7d_remaining_percent,
        CASE
            WHEN (CASE WHEN r.account_id IS NOT NULL THEN COALESCE(r.primary_success, FALSE) ELSE s.used_primary IS NOT NULL END)
             AND s.used_primary IS NOT NULL
            THEN ROUND(GREATEST(0, LEAST(100, 100 - s.used_primary)), 2)
        END AS codex_primary_remaining_percent,
        CASE
            WHEN (CASE WHEN r.account_id IS NOT NULL THEN COALESCE(r.secondary_success, FALSE) ELSE s.used_secondary IS NOT NULL END)
             AND s.used_secondary IS NOT NULL
            THEN ROUND(GREATEST(0, LEAST(100, 100 - s.used_secondary)), 2)
        END AS codex_secondary_remaining_percent,
        CASE
            WHEN (CASE WHEN r.account_id IS NOT NULL THEN COALESCE(r.five_hour_success, FALSE) ELSE s.used_5h IS NOT NULL END)
            THEN s.raw_codex_5h_reset_at
        END AS codex_5h_reset_at,
        CASE
            WHEN (CASE WHEN r.account_id IS NOT NULL THEN COALESCE(r.seven_day_success, FALSE) ELSE s.used_7d IS NOT NULL END)
            THEN s.raw_codex_7d_reset_at
        END AS codex_7d_reset_at,
        CASE
            WHEN (CASE WHEN r.account_id IS NOT NULL THEN COALESCE(r.five_hour_success, FALSE) ELSE s.used_5h IS NOT NULL END)
            THEN s.raw_reset_5h_after_seconds
        END AS codex_5h_reset_after_seconds,
        CASE
            WHEN (CASE WHEN r.account_id IS NOT NULL THEN COALESCE(r.seven_day_success, FALSE) ELSE s.used_7d IS NOT NULL END)
            THEN s.raw_reset_7d_after_seconds
        END AS codex_7d_reset_after_seconds,
        COALESCE(s.window_5h_minutes, 300) AS codex_5h_window_minutes,
        COALESCE(s.window_7d_minutes, 10080) AS codex_7d_window_minutes,
        CASE
            WHEN (CASE WHEN r.account_id IS NOT NULL THEN COALESCE(r.primary_success, FALSE) ELSE s.used_primary IS NOT NULL END)
            THEN s.raw_primary_reset_after_seconds
        END AS codex_primary_reset_after_seconds,
        CASE
            WHEN (CASE WHEN r.account_id IS NOT NULL THEN COALESCE(r.secondary_success, FALSE) ELSE s.used_secondary IS NOT NULL END)
            THEN s.raw_secondary_reset_after_seconds
        END AS codex_secondary_reset_after_seconds,
        COALESCE(s.window_primary_minutes, 10080) AS codex_primary_window_minutes,
        COALESCE(s.window_secondary_minutes, 300) AS codex_secondary_window_minutes
    FROM source AS s
    LEFT JOIN refresh_state AS r
      ON r.account_id = s.id
),
view_rows AS (
    SELECT
        *,
        CASE
            WHEN codex_5h_reset_after_seconds IS NOT NULL
             AND codex_5h_reset_after_seconds > 0
             AND usage_updated_at_ts IS NOT NULL
            THEN usage_updated_at_ts + (codex_5h_reset_after_seconds * interval '1 second')
            WHEN codex_5h_reset_at ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
             AND codex_5h_window_minutes > 0
            THEN CASE
                WHEN codex_5h_reset_at::timestamptz > now() THEN codex_5h_reset_at::timestamptz
                ELSE codex_5h_reset_at::timestamptz +
                    (
                        (floor(EXTRACT(EPOCH FROM now() - codex_5h_reset_at::timestamptz) / (codex_5h_window_minutes * 60.0))::BIGINT + 1)
                        * (codex_5h_window_minutes * interval '1 minute')
                    )
            END
        END AS codex_5h_next_reset_at,
        CASE
            WHEN codex_7d_reset_after_seconds IS NOT NULL
             AND codex_7d_reset_after_seconds > 0
             AND usage_updated_at_ts IS NOT NULL
            THEN usage_updated_at_ts + (codex_7d_reset_after_seconds * interval '1 second')
            WHEN codex_7d_reset_at ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'
             AND codex_7d_window_minutes > 0
            THEN CASE
                WHEN codex_7d_reset_at::timestamptz > now() THEN codex_7d_reset_at::timestamptz
                ELSE codex_7d_reset_at::timestamptz +
                    (
                        (floor(EXTRACT(EPOCH FROM now() - codex_7d_reset_at::timestamptz) / (codex_7d_window_minutes * 60.0))::BIGINT + 1)
                        * (codex_7d_window_minutes * interval '1 minute')
                    )
            END
        END AS codex_7d_next_reset_at
    FROM base
),
enriched AS (
    SELECT
        *,
        COALESCE(codex_7d_remaining_percent, codex_primary_remaining_percent) AS weekly_remaining_percent,
        COALESCE(codex_5h_remaining_percent, codex_secondary_remaining_percent) AS five_hour_remaining_percent,
        COALESCE(
            CASE
                WHEN codex_primary_reset_after_seconds IS NOT NULL
                 AND codex_primary_reset_after_seconds > 0
                 AND usage_updated_at_ts IS NOT NULL
                THEN usage_updated_at_ts + (codex_primary_reset_after_seconds * interval '1 second')
            END,
            codex_7d_next_reset_at
        ) AS codex_primary_next_reset_at,
        COALESCE(
            CASE
                WHEN codex_secondary_reset_after_seconds IS NOT NULL
                 AND codex_secondary_reset_after_seconds > 0
                 AND usage_updated_at_ts IS NOT NULL
                THEN usage_updated_at_ts + (codex_secondary_reset_after_seconds * interval '1 second')
            END,
            codex_5h_next_reset_at
        ) AS codex_secondary_next_reset_at,
        (
            codex_5h_remaining_percent IS NOT NULL
            OR codex_7d_remaining_percent IS NOT NULL
            OR codex_primary_remaining_percent IS NOT NULL
            OR codex_secondary_remaining_percent IS NOT NULL
        ) AS has_quota_data,
        (
            five_hour_success
            OR seven_day_success
            OR primary_success
            OR secondary_success
        ) AS has_quota_success
    FROM view_rows
),
classified AS (
    SELECT
        *,
        COALESCE(codex_7d_next_reset_at, codex_primary_next_reset_at) AS weekly_next_reset_at,
        COALESCE(codex_5h_next_reset_at, codex_secondary_next_reset_at) AS five_hour_next_reset_at,
        CASE
            WHEN temp_unschedulable_until IS NOT NULL AND temp_unschedulable_until > now()
            THEN temp_unschedulable_until
        END AS temp_block_until,
        CASE
            WHEN overload_until IS NOT NULL AND overload_until > now()
            THEN overload_until
        END AS overload_block_until,
        CASE
            WHEN rate_limit_reset_at IS NOT NULL AND rate_limit_reset_at > now()
            THEN rate_limit_reset_at
        END AS rate_limit_block_until,
        CASE
            WHEN COALESCE(codex_7d_remaining_percent, codex_primary_remaining_percent) <= 0
            THEN COALESCE(codex_7d_next_reset_at, codex_primary_next_reset_at)
        END AS weekly_recovery_at,
        CASE
            WHEN COALESCE(codex_5h_remaining_percent, codex_secondary_remaining_percent) <= 0
            THEN COALESCE(codex_5h_next_reset_at, codex_secondary_next_reset_at)
        END AS five_hour_recovery_at,
        CASE
            WHEN status = 'active'
             AND quota_refresh_status IN ('success', 'partial', 'cached')
             AND has_quota_data
            THEN TRUE
            ELSE FALSE
        END AS alive,
        CASE
            WHEN status = 'active' AND schedulable IS DISTINCT FROM TRUE
            THEN TRUE
            ELSE FALSE
        END AS dispatch_disabled,
        CASE
            WHEN status <> 'active' THEN TRUE
            ELSE FALSE
        END AS inactive_state,
        (
            SELECT MIN(candidate_ts)
            FROM (
                VALUES
                    (CASE
                        WHEN temp_unschedulable_until IS NOT NULL AND temp_unschedulable_until > now()
                        THEN temp_unschedulable_until
                    END),
                    (CASE
                        WHEN overload_until IS NOT NULL AND overload_until > now()
                        THEN overload_until
                    END),
                    (CASE
                        WHEN rate_limit_reset_at IS NOT NULL AND rate_limit_reset_at > now()
                        THEN rate_limit_reset_at
                    END),
                    (CASE
                        WHEN COALESCE(codex_7d_remaining_percent, codex_primary_remaining_percent) <= 0
                        THEN COALESCE(codex_7d_next_reset_at, codex_primary_next_reset_at)
                    END),
                    (CASE
                        WHEN COALESCE(codex_5h_remaining_percent, codex_secondary_remaining_percent) <= 0
                        THEN COALESCE(codex_5h_next_reset_at, codex_secondary_next_reset_at)
                    END)
            ) AS recovery_candidates(candidate_ts)
            WHERE candidate_ts IS NOT NULL
        ) AS earliest_recovery_at
    FROM enriched
),
state_rows AS (
    SELECT
        *,
        CASE
            WHEN status <> 'active' THEN 'failed'
            WHEN schedulable IS DISTINCT FROM TRUE THEN 'failed'
            WHEN quota_refresh_status = 'failed' THEN 'failed'
            WHEN NOT has_quota_data THEN 'untracked'
            WHEN (
                temp_block_until IS NOT NULL
                OR overload_block_until IS NOT NULL
                OR rate_limit_block_until IS NOT NULL
                OR COALESCE(weekly_remaining_percent, 100) <= 0
                OR COALESCE(five_hour_remaining_percent, 100) <= 0
            ) AND earliest_recovery_at IS NOT NULL AND earliest_recovery_at > now() THEN 'recovering'
            WHEN (
                rate_limited_at IS NOT NULL
                OR COALESCE(weekly_remaining_percent, 100) <= 0
                OR COALESCE(five_hour_remaining_percent, 100) <= 0
                OR effective_schedulable IS DISTINCT FROM TRUE
            ) THEN 'quota_limited'
            ELSE 'healthy'
        END AS state_key,
        CASE
            WHEN status <> 'active' THEN '账号未激活'
            WHEN schedulable IS DISTINCT FROM TRUE THEN '已关闭调度'
            WHEN quota_refresh_status = 'failed' THEN COALESCE(NULLIF(quota_refresh_error, ''), '额度刷新失败')
            WHEN NOT has_quota_data THEN '暂无额度快照'
            WHEN temp_block_until IS NOT NULL THEN COALESCE(NULLIF(temp_unschedulable_reason, ''), '临时不可调度')
            WHEN overload_block_until IS NOT NULL THEN '过载冷却中'
            WHEN rate_limit_block_until IS NOT NULL THEN '限流冷却中'
            WHEN rate_limited_at IS NOT NULL AND rate_limit_reset_at IS NULL THEN '限流未恢复'
            WHEN COALESCE(weekly_remaining_percent, 100) <= 0 THEN '周额度已用尽'
            WHEN COALESCE(five_hour_remaining_percent, 100) <= 0 THEN '5h 额度已用尽'
            WHEN effective_schedulable THEN '正常'
            ELSE '当前不可调度'
        END AS state_reason,
        CASE
            WHEN temp_block_until IS NOT NULL AND temp_block_until = earliest_recovery_at THEN 'temp_unschedulable'
            WHEN overload_block_until IS NOT NULL AND overload_block_until = earliest_recovery_at THEN 'overload'
            WHEN rate_limit_block_until IS NOT NULL AND rate_limit_block_until = earliest_recovery_at THEN 'rate_limit'
            WHEN weekly_recovery_at IS NOT NULL AND weekly_recovery_at = earliest_recovery_at THEN 'weekly'
            WHEN five_hour_recovery_at IS NOT NULL AND five_hour_recovery_at = earliest_recovery_at THEN 'five_hour'
            ELSE NULL
        END AS recovery_source
    FROM classified
),
upsert_latest AS (
    INSERT INTO custom_account_quota_latest (
        account_id,
        account_name,
        platform,
        account_type,
        status,
        schedulable,
        last_used_at,
        rate_limited_at,
        rate_limit_reset_at,
        usage_updated_at,
        codex_5h_used_percent,
        codex_7d_used_percent,
        codex_primary_used_percent,
        codex_secondary_used_percent,
        codex_5h_remaining_percent,
        codex_7d_remaining_percent,
        codex_primary_remaining_percent,
        codex_secondary_remaining_percent,
        codex_5h_reset_at,
        codex_7d_reset_at,
        codex_primary_reset_after_seconds,
        codex_secondary_reset_after_seconds,
        captured_at
    )
    SELECT
        id,
        name,
        platform,
        type,
        status,
        schedulable,
        last_used_at,
        rate_limited_at,
        rate_limit_reset_at,
        usage_updated_at,
        codex_5h_used_percent,
        codex_7d_used_percent,
        codex_primary_used_percent,
        codex_secondary_used_percent,
        codex_5h_remaining_percent,
        codex_7d_remaining_percent,
        codex_primary_remaining_percent,
        codex_secondary_remaining_percent,
        codex_5h_reset_at,
        codex_7d_reset_at,
        codex_primary_reset_after_seconds,
        codex_secondary_reset_after_seconds,
        now()
    FROM state_rows
    ON CONFLICT (account_id) DO UPDATE SET
        account_name = EXCLUDED.account_name,
        platform = EXCLUDED.platform,
        account_type = EXCLUDED.account_type,
        status = EXCLUDED.status,
        schedulable = EXCLUDED.schedulable,
        last_used_at = EXCLUDED.last_used_at,
        rate_limited_at = EXCLUDED.rate_limited_at,
        rate_limit_reset_at = EXCLUDED.rate_limit_reset_at,
        usage_updated_at = EXCLUDED.usage_updated_at,
        codex_5h_used_percent = EXCLUDED.codex_5h_used_percent,
        codex_7d_used_percent = EXCLUDED.codex_7d_used_percent,
        codex_primary_used_percent = EXCLUDED.codex_primary_used_percent,
        codex_secondary_used_percent = EXCLUDED.codex_secondary_used_percent,
        codex_5h_remaining_percent = EXCLUDED.codex_5h_remaining_percent,
        codex_7d_remaining_percent = EXCLUDED.codex_7d_remaining_percent,
        codex_primary_remaining_percent = EXCLUDED.codex_primary_remaining_percent,
        codex_secondary_remaining_percent = EXCLUDED.codex_secondary_remaining_percent,
        codex_5h_reset_at = EXCLUDED.codex_5h_reset_at,
        codex_7d_reset_at = EXCLUDED.codex_7d_reset_at,
        codex_primary_reset_after_seconds = EXCLUDED.codex_primary_reset_after_seconds,
        codex_secondary_reset_after_seconds = EXCLUDED.codex_secondary_reset_after_seconds,
        captured_at = EXCLUDED.captured_at
    RETURNING 1
),
summary AS (
    SELECT
        COUNT(*)::INTEGER AS total_accounts,
        COUNT(*) FILTER (WHERE status = 'active')::INTEGER AS active_accounts,
        COUNT(*) FILTER (WHERE alive)::INTEGER AS alive_accounts,
        COUNT(*) FILTER (WHERE has_quota_data)::INTEGER AS tracked_accounts,
        COUNT(*) FILTER (WHERE effective_schedulable)::INTEGER AS schedulable_accounts,
        COUNT(*) FILTER (
            WHERE effective_schedulable
              AND has_quota_data
        )::INTEGER AS schedulable_tracked_accounts,
        COUNT(*) FILTER (WHERE codex_5h_remaining_percent IS NOT NULL)::INTEGER AS tracked_5h_accounts,
        COUNT(*) FILTER (WHERE weekly_remaining_percent IS NOT NULL)::INTEGER AS tracked_7d_accounts,
        COUNT(*) FILTER (WHERE effective_schedulable AND codex_5h_remaining_percent IS NOT NULL)::INTEGER AS schedulable_tracked_5h_accounts,
        COUNT(*) FILTER (WHERE effective_schedulable AND weekly_remaining_percent IS NOT NULL)::INTEGER AS schedulable_tracked_7d_accounts,
        COUNT(*) FILTER (WHERE state_key = 'healthy')::INTEGER AS healthy_accounts,
        COUNT(*) FILTER (WHERE state_key = 'recovering')::INTEGER AS recovering_accounts,
        COUNT(*) FILTER (WHERE state_key = 'quota_limited')::INTEGER AS quota_limited_accounts,
        COUNT(*) FILTER (WHERE state_key = 'failed')::INTEGER AS failed_accounts,
        COUNT(*) FILTER (WHERE state_key = 'untracked')::INTEGER AS untracked_accounts,
        COUNT(*) FILTER (WHERE dispatch_disabled)::INTEGER AS disabled_accounts,
        COUNT(*) FILTER (WHERE inactive_state)::INTEGER AS inactive_accounts,
        COUNT(*) FILTER (WHERE quota_refresh_status = 'success')::INTEGER AS refresh_success_accounts,
        COUNT(*) FILTER (WHERE quota_refresh_status = 'partial')::INTEGER AS refresh_partial_accounts,
        COUNT(*) FILTER (WHERE quota_refresh_status = 'failed')::INTEGER AS refresh_failed_accounts,
        ROUND(AVG(codex_5h_remaining_percent), 2) AS avg_all_5h_remaining_pct,
        ROUND(AVG(weekly_remaining_percent), 2) AS avg_all_7d_remaining_pct,
        ROUND(AVG(codex_primary_remaining_percent), 2) AS avg_all_primary_remaining_pct,
        ROUND(AVG(codex_secondary_remaining_percent), 2) AS avg_all_secondary_remaining_pct,
        ROUND(AVG(codex_5h_remaining_percent) FILTER (WHERE effective_schedulable), 2) AS avg_5h_remaining_pct,
        ROUND(AVG(weekly_remaining_percent) FILTER (WHERE effective_schedulable), 2) AS avg_7d_remaining_pct,
        ROUND(AVG(codex_primary_remaining_percent) FILTER (WHERE effective_schedulable), 2) AS avg_primary_remaining_pct,
        ROUND(AVG(codex_secondary_remaining_percent) FILTER (WHERE effective_schedulable), 2) AS avg_secondary_remaining_pct,
        ROUND(SUM(codex_5h_remaining_percent / 100), 2) AS total_all_5h_equiv_accounts,
        ROUND(SUM(weekly_remaining_percent / 100), 2) AS total_all_7d_equiv_accounts,
        ROUND(SUM(codex_primary_remaining_percent / 100), 2) AS total_all_primary_equiv_accounts,
        ROUND(SUM(codex_secondary_remaining_percent / 100), 2) AS total_all_secondary_equiv_accounts,
        ROUND(SUM(codex_5h_remaining_percent / 100) FILTER (WHERE effective_schedulable), 2) AS total_5h_equiv_accounts,
        ROUND(SUM(weekly_remaining_percent / 100) FILTER (WHERE effective_schedulable), 2) AS total_7d_equiv_accounts,
        ROUND(SUM(codex_primary_remaining_percent / 100) FILTER (WHERE effective_schedulable), 2) AS total_primary_equiv_accounts,
        ROUND(SUM(codex_secondary_remaining_percent / 100) FILTER (WHERE effective_schedulable), 2) AS total_secondary_equiv_accounts,
        CASE
            WHEN COUNT(*) = 0 THEN NULL
            ELSE ROUND((COUNT(*) FILTER (WHERE alive))::NUMERIC * 100 / COUNT(*), 2)
        END AS survival_rate_pct,
        CASE
            WHEN COUNT(*) = 0 THEN NULL
            ELSE ROUND((COUNT(*) FILTER (WHERE state_key = 'healthy'))::NUMERIC * 100 / COUNT(*), 2)
        END AS health_rate_pct
    FROM state_rows
),
insert_summary AS (
    INSERT INTO custom_account_quota_summary_snapshots (
        total_accounts,
        tracked_accounts,
        tracked_5h_accounts,
        tracked_7d_accounts,
        avg_5h_remaining_pct,
        avg_7d_remaining_pct,
        avg_primary_remaining_pct,
        avg_secondary_remaining_pct,
        total_5h_equiv_accounts,
        total_7d_equiv_accounts,
        total_primary_equiv_accounts,
        total_secondary_equiv_accounts
    )
    SELECT
        total_accounts,
        tracked_accounts,
        tracked_5h_accounts,
        tracked_7d_accounts,
        avg_5h_remaining_pct,
        avg_7d_remaining_pct,
        avg_primary_remaining_pct,
        avg_secondary_remaining_pct,
        total_5h_equiv_accounts,
        total_7d_equiv_accounts,
        total_primary_equiv_accounts,
        total_secondary_equiv_accounts
    FROM summary
    RETURNING id
),
insert_health AS (
    INSERT INTO custom_account_quota_health_snapshots (
        total_accounts,
        active_accounts,
        alive_accounts,
        tracked_accounts,
        schedulable_accounts,
        schedulable_tracked_accounts,
        tracked_5h_accounts,
        tracked_7d_accounts,
        schedulable_tracked_5h_accounts,
        schedulable_tracked_7d_accounts,
        healthy_accounts,
        recovering_accounts,
        quota_limited_accounts,
        failed_accounts,
        untracked_accounts,
        disabled_accounts,
        inactive_accounts,
        refresh_success_accounts,
        refresh_partial_accounts,
        refresh_failed_accounts,
        avg_all_5h_remaining_pct,
        avg_all_7d_remaining_pct,
        avg_5h_remaining_pct,
        avg_7d_remaining_pct,
        total_all_5h_equiv_accounts,
        total_all_7d_equiv_accounts,
        total_5h_equiv_accounts,
        total_7d_equiv_accounts
    )
    SELECT
        total_accounts,
        active_accounts,
        alive_accounts,
        tracked_accounts,
        schedulable_accounts,
        schedulable_tracked_accounts,
        tracked_5h_accounts,
        tracked_7d_accounts,
        schedulable_tracked_5h_accounts,
        schedulable_tracked_7d_accounts,
        healthy_accounts,
        recovering_accounts,
        quota_limited_accounts,
        failed_accounts,
        untracked_accounts,
        disabled_accounts,
        inactive_accounts,
        refresh_success_accounts,
        refresh_partial_accounts,
        refresh_failed_accounts,
        avg_all_5h_remaining_pct,
        avg_all_7d_remaining_pct,
        avg_5h_remaining_pct,
        avg_7d_remaining_pct,
        total_all_5h_equiv_accounts,
        total_all_7d_equiv_accounts,
        total_5h_equiv_accounts,
        total_7d_equiv_accounts
    FROM summary
    RETURNING id
),
plan_rollup AS (
    SELECT
        plan_type,
        CASE
            WHEN plan_type = 'free' THEN 0
            WHEN plan_type = 'plus' THEN 1
            WHEN plan_type = 'pro' THEN 2
            WHEN plan_type = 'team' THEN 3
            WHEN plan_type = 'business' THEN 4
            WHEN plan_type = 'enterprise' THEN 5
            ELSE 10
        END AS plan_rank,
        COUNT(*)::INTEGER AS account_count,
        COUNT(*) FILTER (WHERE effective_schedulable)::INTEGER AS schedulable_account_count,
        COUNT(*) FILTER (WHERE state_key = 'healthy')::INTEGER AS healthy_accounts,
        COUNT(*) FILTER (WHERE state_key = 'recovering')::INTEGER AS recovering_accounts,
        COUNT(*) FILTER (WHERE state_key = 'quota_limited')::INTEGER AS quota_limited_accounts,
        COUNT(*) FILTER (WHERE state_key = 'failed')::INTEGER AS failed_accounts,
        COUNT(*) FILTER (WHERE state_key = 'untracked')::INTEGER AS untracked_accounts,
        (COUNT(*) FILTER (WHERE codex_5h_remaining_percent IS NOT NULL) > 0) AS five_hour_supported,
        COUNT(*) FILTER (WHERE codex_5h_remaining_percent IS NOT NULL)::INTEGER AS five_hour_success_count,
        COUNT(*) FILTER (WHERE codex_5h_remaining_percent IS NULL)::INTEGER AS five_hour_failed_count,
        ROUND(SUM(codex_5h_remaining_percent), 2) AS five_hour_total_remaining_percent,
        MIN(COALESCE(codex_5h_next_reset_at, codex_secondary_next_reset_at)) FILTER (
            WHERE COALESCE(codex_5h_next_reset_at, codex_secondary_next_reset_at) IS NOT NULL
        ) AS five_hour_reset_at,
        COUNT(*) FILTER (
            WHERE effective_schedulable AND codex_5h_remaining_percent IS NOT NULL
        )::INTEGER AS five_hour_schedulable_success_count,
        ROUND(SUM(codex_5h_remaining_percent) FILTER (WHERE effective_schedulable), 2) AS five_hour_schedulable_total_remaining_percent,
        TRUE AS weekly_supported,
        COUNT(*) FILTER (WHERE weekly_remaining_percent IS NOT NULL)::INTEGER AS weekly_success_count,
        COUNT(*) FILTER (WHERE weekly_remaining_percent IS NULL)::INTEGER AS weekly_failed_count,
        ROUND(SUM(weekly_remaining_percent), 2) AS weekly_total_remaining_percent,
        MIN(COALESCE(codex_7d_next_reset_at, codex_primary_next_reset_at)) FILTER (
            WHERE COALESCE(codex_7d_next_reset_at, codex_primary_next_reset_at) IS NOT NULL
        ) AS weekly_reset_at,
        COUNT(*) FILTER (
            WHERE effective_schedulable AND weekly_remaining_percent IS NOT NULL
        )::INTEGER AS weekly_schedulable_success_count,
        ROUND(SUM(weekly_remaining_percent) FILTER (WHERE effective_schedulable), 2) AS weekly_schedulable_total_remaining_percent
    FROM state_rows
    GROUP BY plan_type
),
plan_json AS (
    SELECT
        plan_rank,
        plan_type,
        jsonb_build_object(
            'plan_type', plan_type,
            'account_count', account_count,
            'schedulable_account_count', schedulable_account_count,
            'healthy_accounts', healthy_accounts,
            'recovering_accounts', recovering_accounts,
            'quota_limited_accounts', quota_limited_accounts,
            'failed_accounts', failed_accounts,
            'untracked_accounts', untracked_accounts,
            'five_hour', jsonb_build_object(
                'supported', five_hour_supported,
                'reset_at', five_hour_reset_at,
                'success_count', five_hour_success_count,
                'failed_count', five_hour_failed_count,
                'total_remaining_percent', five_hour_total_remaining_percent,
                'avg_remaining_percent', CASE
                    WHEN five_hour_success_count > 0 THEN ROUND(five_hour_total_remaining_percent / five_hour_success_count, 2)
                END,
                'schedulable_success_count', five_hour_schedulable_success_count,
                'schedulable_total_remaining_percent', five_hour_schedulable_total_remaining_percent,
                'schedulable_avg_remaining_percent', CASE
                    WHEN five_hour_schedulable_success_count > 0 THEN ROUND(five_hour_schedulable_total_remaining_percent / five_hour_schedulable_success_count, 2)
                END
            ),
            'weekly', jsonb_build_object(
                'supported', weekly_supported,
                'reset_at', weekly_reset_at,
                'success_count', weekly_success_count,
                'failed_count', weekly_failed_count,
                'total_remaining_percent', weekly_total_remaining_percent,
                'avg_remaining_percent', CASE
                    WHEN weekly_success_count > 0 THEN ROUND(weekly_total_remaining_percent / weekly_success_count, 2)
                END,
                'schedulable_success_count', weekly_schedulable_success_count,
                'schedulable_total_remaining_percent', weekly_schedulable_total_remaining_percent,
                'schedulable_avg_remaining_percent', CASE
                    WHEN weekly_schedulable_success_count > 0 THEN ROUND(weekly_schedulable_total_remaining_percent / weekly_schedulable_success_count, 2)
                END
            )
        ) AS payload
    FROM plan_rollup
),
history_rows AS (
    SELECT
        id,
        captured_at,
        total_accounts,
        active_accounts,
        alive_accounts,
        tracked_accounts,
        schedulable_accounts,
        schedulable_tracked_accounts,
        tracked_5h_accounts,
        tracked_7d_accounts,
        schedulable_tracked_5h_accounts,
        schedulable_tracked_7d_accounts,
        healthy_accounts,
        recovering_accounts,
        quota_limited_accounts,
        failed_accounts,
        untracked_accounts,
        disabled_accounts,
        inactive_accounts,
        refresh_success_accounts,
        refresh_partial_accounts,
        refresh_failed_accounts,
        avg_all_5h_remaining_pct,
        avg_all_7d_remaining_pct,
        avg_5h_remaining_pct,
        avg_7d_remaining_pct,
        total_all_5h_equiv_accounts,
        total_all_7d_equiv_accounts,
        total_5h_equiv_accounts,
        total_7d_equiv_accounts
    FROM custom_account_quota_health_snapshots
    ORDER BY captured_at DESC
    LIMIT 96
),
cleanup_summary AS (
    DELETE FROM custom_account_quota_summary_snapshots
    WHERE captured_at < now() - interval '90 days'
    RETURNING 1
),
cleanup_health AS (
    DELETE FROM custom_account_quota_health_snapshots
    WHERE captured_at < now() - interval '90 days'
    RETURNING 1
)
SELECT jsonb_build_object(
    'generated_at', now(),
    'latest_rows_persisted', (SELECT COUNT(*) FROM upsert_latest),
    'summary_snapshot_id', (SELECT id FROM insert_summary LIMIT 1),
    'health_snapshot_id', (SELECT id FROM insert_health LIMIT 1),
    'summary', (SELECT to_jsonb(summary) FROM summary),
    'plans', COALESCE((
        SELECT jsonb_agg(payload ORDER BY plan_rank, plan_type)
        FROM plan_json
    ), '[]'::jsonb),
    'history', COALESCE((
        SELECT jsonb_agg(to_jsonb(history_rows) ORDER BY captured_at DESC)
        FROM history_rows
    ), '[]'::jsonb),
    'accounts', COALESCE((
        SELECT jsonb_agg(
            to_jsonb(account_rows)
            ORDER BY
                CASE state_key
                    WHEN 'failed' THEN 0
                    WHEN 'recovering' THEN 1
                    WHEN 'quota_limited' THEN 2
                    WHEN 'healthy' THEN 3
                    ELSE 4
                END,
                CASE WHEN weekly_remaining_percent IS NULL THEN 1 ELSE 0 END,
                weekly_remaining_percent ASC,
                earliest_recovery_at NULLS LAST,
                id ASC
        )
        FROM (
            SELECT
                id,
                name,
                platform,
                type,
                plan_type,
                status,
                schedulable,
                effective_schedulable,
                alive,
                has_quota_data,
                state_key,
                state_reason,
                recovery_source,
                earliest_recovery_at,
                weekly_recovery_at,
                five_hour_recovery_at,
                last_used_at,
                rate_limited_at,
                rate_limit_reset_at,
                temp_unschedulable_until,
                temp_unschedulable_reason,
                overload_until,
                usage_updated_at,
                quota_refresh_status,
                quota_refresh_error,
                quota_refreshed_at,
                five_hour_success,
                seven_day_success,
                primary_success,
                secondary_success,
                codex_5h_used_percent,
                codex_7d_used_percent,
                codex_primary_used_percent,
                codex_secondary_used_percent,
                codex_5h_remaining_percent,
                codex_7d_remaining_percent,
                codex_primary_remaining_percent,
                codex_secondary_remaining_percent,
                five_hour_remaining_percent,
                weekly_remaining_percent,
                COALESCE(weekly_remaining_percent, 100) <= 0 AS weekly_limited,
                COALESCE(five_hour_remaining_percent, 100) <= 0 AS five_hour_limited,
                codex_5h_reset_at,
                codex_7d_reset_at,
                codex_5h_next_reset_at,
                codex_7d_next_reset_at,
                codex_primary_next_reset_at,
                codex_secondary_next_reset_at,
                five_hour_next_reset_at,
                weekly_next_reset_at,
                codex_5h_reset_after_seconds,
                codex_7d_reset_after_seconds,
                codex_primary_reset_after_seconds,
                codex_secondary_reset_after_seconds
            FROM state_rows
        ) AS account_rows
    ), '[]'::jsonb)
)::TEXT;
