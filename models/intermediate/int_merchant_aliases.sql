with shipped as (
    select
        alias_key,
        lower(match_type) as match_type,
        {{ normalize_text('match_value') }} as match_value,
        merchant_name,
        nullif(taxonomy_key, '') as taxonomy_key,
        cast(enabled as boolean) as enabled,
        0 as source_priority
    from {{ ref('merchant_aliases') }}
)

{% if var('enable_local_seeds', false) %}
,
local as (
    select
        alias_key,
        lower(match_type) as match_type,
        {{ normalize_text('match_value') }} as match_value,
        merchant_name,
        nullif(taxonomy_key, '') as taxonomy_key,
        cast(enabled as boolean) as enabled,
        1 as source_priority
    from {{ builtins.ref('local_merchant_aliases') }}
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
            partition by alias_key
            order by source_priority desc
        ) as row_number
    from combined
)
where row_number = 1
  and enabled
