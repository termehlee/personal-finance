with source as (
    select * from {{ source('raw', 'raw_transactions') }}
),

renamed as (
    select
        transaction_id,
        file_sha256,
        source_file,
        bank_folder,
        account_slug,
        cast(transaction_date as date) as transaction_date,
        cast(posting_date as date) as posting_date,
        trim(description) as description,
        {{ normalize_text('description') }} as normalized_description,
        cast(amount as decimal(18, 2)) as amount,
        nullif(upper(trim(currency)), '') as transaction_currency,
        lower(trim(direction)) as direction,
        cast(balance as decimal(18, 2)) as balance,
        cast(loaded_at as timestamp) as loaded_at
    from source
)

select * from renamed
