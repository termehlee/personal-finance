with shipped as (
    select
        rule_key,
        lower(match_type) as match_type,
        {{ normalize_text('match_value') }} as match_value,
        taxonomy_key,
        cast(priority as integer) as priority,
        cast(is_transfer as boolean) as is_transfer,
        cast(enabled as boolean) as enabled,
        0 as source_priority
    from {{ ref('category_rules') }}
)

{% if var('enable_local_seeds', false) %}
,
local as (
    select
        rule_key,
        lower(match_type) as match_type,
        {{ normalize_text('match_value') }} as match_value,
        taxonomy_key,
        cast(priority as integer) as priority,
        cast(is_transfer as boolean) as is_transfer,
        cast(enabled as boolean) as enabled,
        1 as source_priority
    from {{ builtins.ref('local_category_rules') }}
),
combined as (
    select * from shipped union all select * from local
)
{% else %}
,
combined as (
    select * from shipped
)
{% endif %}

select * exclude (source_priority, row_number)
from (
    select
        *,
        row_number() over (
            partition by rule_key
            order by source_priority desc
        ) as row_number
    from combined
)
where row_number = 1
  and enabled
