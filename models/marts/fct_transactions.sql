with transactions as (
    select * from {{ ref('int_transactions_categorised') }}
),

accounts as (
    select * from {{ ref('int_accounts') }}
)

select
    transactions.transaction_id,
    transactions.transaction_date,
    transactions.posting_date,
    transactions.account_slug,
    accounts.account_name,
    accounts.bank_name,
    accounts.account_type,
    coalesce(
        transactions.transaction_currency,
        accounts.currency,
        upper('{{ var("base_currency") }}')
    ) as currency,
    transactions.description,
    transactions.normalized_description,
    transactions.merchant_name,
    transactions.category,
    transactions.subcategory,
    transactions.direction,
    transactions.amount,
    case when transactions.direction = 'credit' then transactions.amount else 0 end as inflow_amount,
    case when transactions.direction = 'debit' then abs(transactions.amount) else 0 end as outflow_amount,
    transactions.is_transfer,
    transactions.categorisation_method,
    transactions.categorisation_key,
    transactions.category != '{{ var("uncategorised_label") }}' as is_categorised,
    case
        when transactions.direction = 'credit'
            and not transactions.is_transfer
            and transactions.category != '{{ var("uncategorised_label") }}'
            then transactions.amount
        else 0
    end as income_amount,
    case
        when transactions.direction = 'debit'
            and not transactions.is_transfer
            and transactions.category != '{{ var("uncategorised_label") }}'
            then abs(transactions.amount)
        else 0
    end as spend_amount,
    transactions.duplicate_candidate_key,
    transactions.duplicate_candidate_count,
    transactions.is_duplicate_candidate,
    transactions.file_sha256,
    transactions.source_file,
    transactions.loaded_at
from transactions
left join accounts
    on transactions.account_slug = accounts.account_slug
