select
    date_trunc('month', transaction_date)::date as month,
    currency,
    sum(income_amount) as income_amount,
    sum(spend_amount) as spend_amount,
    sum(income_amount) - sum(spend_amount) as net_amount,
    case
        when sum(income_amount) = 0 then null
        else (sum(income_amount) - sum(spend_amount)) / sum(income_amount)
    end as savings_rate,
    count(*) as transaction_count,
    count(*) filter (where not is_categorised) as uncategorised_transaction_count
from {{ ref('fct_transactions') }}
group by 1, 2
