with source as (
    select * from {{ source('raw', 'raw_statements') }}
)

select
    file_sha256,
    source_file,
    bank_folder,
    account_slug,
    monopoly_bank,
    statement_type,
    cast(period_start as date) as period_start,
    cast(period_end as date) as period_end,
    schema_version,
    payment_summary,
    balances,
    cast(loaded_at as timestamp) as loaded_at
from source
