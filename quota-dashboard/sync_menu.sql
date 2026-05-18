WITH current_items AS (
    SELECT COALESCE(
        (SELECT value::jsonb FROM settings WHERE key = 'custom_menu_items'),
        '[]'::jsonb
    ) AS items
),
filtered_items AS (
    SELECT COALESCE(jsonb_agg(item), '[]'::jsonb) AS items
    FROM current_items,
         LATERAL jsonb_array_elements(items) AS item
    WHERE item->>'id' <> :'menu_id'
),
merged_items AS (
    SELECT items || jsonb_build_array(
        jsonb_strip_nulls(
            jsonb_build_object(
                'id', :'menu_id',
                'label', :'menu_label',
                'url', :'menu_url',
                'visibility', :'menu_visibility',
                'icon_svg', NULLIF(:'menu_icon_svg', '')
            )
        )
    ) AS items
    FROM filtered_items
)
INSERT INTO settings (key, value, updated_at)
VALUES (
    'custom_menu_items',
    (SELECT items::text FROM merged_items),
    now()
)
ON CONFLICT (key) DO UPDATE
SET value = EXCLUDED.value,
    updated_at = now();
