select
    transaction_id,
    transaction_date,
    account_slug,
    currency,
    description,
    merchant_name,
    direction,
    amount,
    duplicate_candidate_key,
    is_duplicate_candidate,
    source_file
from {{ ref('fct_transactions') }}
where not is_categorised
