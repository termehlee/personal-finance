select
    date_trunc('month', transaction_date)::date as month,
    currency,
    merchant_name,
    sum(spend_amount) as spend_amount,
    count(*) as transaction_count
from {{ ref('fct_transactions') }}
where spend_amount > 0
group by 1, 2, 3
