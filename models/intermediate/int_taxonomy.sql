with shipped as (
    select
        taxonomy_key,
        category,
        subcategory,
        cast(enabled as boolean) as enabled,
        0 as source_priority
    from {{ ref('taxonomy') }}
)

{% if var('enable_local_seeds', false) %}
,
local as (
    select
        taxonomy_key,
        category,
        subcategory,
        cast(enabled as boolean) as enabled,
        1 as source_priority
    from {{ builtins.ref('local_taxonomy') }}
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
            partition by taxonomy_key
            order by source_priority desc
        ) as row_number
    from combined
)
where row_number = 1
  and enabled
