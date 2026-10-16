select
    date_trunc('month', transaction_date)::date as month,
    currency,
    category,
    subcategory,
    sum(income_amount) as income_amount,
    sum(spend_amount) as spend_amount,
    count(*) as transaction_count
from {{ ref('fct_transactions') }}
where is_categorised
  and not is_transfer
group by 1, 2, 3, 4
