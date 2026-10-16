with shipped as (
    select
        cast(transaction_id as varchar) as transaction_id,
        nullif(cast(merchant_name as varchar), '') as merchant_name,
        nullif(cast(category as varchar), '') as category,
        nullif(cast(subcategory as varchar), '') as subcategory,
        cast(is_transfer as boolean) as is_transfer,
        cast(enabled as boolean) as enabled,
        0 as source_priority
    from {{ ref('transaction_overrides') }}
)

{% if var('enable_local_seeds', false) %}
,
local as (
    select
        cast(transaction_id as varchar) as transaction_id,
        nullif(cast(merchant_name as varchar), '') as merchant_name,
        nullif(cast(category as varchar), '') as category,
        nullif(cast(subcategory as varchar), '') as subcategory,
        cast(is_transfer as boolean) as is_transfer,
        cast(enabled as boolean) as enabled,
        1 as source_priority
    from {{ builtins.ref('local_transaction_overrides') }}
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
            partition by transaction_id
            order by source_priority desc
        ) as row_number
    from combined
)
where row_number = 1
  and enabled
