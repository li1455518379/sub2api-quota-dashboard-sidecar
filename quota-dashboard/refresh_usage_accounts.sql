SELECT id
FROM accounts
WHERE deleted_at IS NULL
  AND platform = 'openai'
  AND type = 'oauth'
ORDER BY
  CASE WHEN extra ? 'codex_usage_updated_at' THEN 1 ELSE 0 END,
  extra->>'codex_usage_updated_at' NULLS FIRST,
  id ASC
LIMIT COALESCE(NULLIF(:'batch_size', '')::INTEGER, 1000);
