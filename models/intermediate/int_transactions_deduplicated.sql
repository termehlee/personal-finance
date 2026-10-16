with ranked as (
    select
        transactions.*,
        md5(
            concat_ws(
                '|',
                account_slug,
                cast(transaction_date as varchar),
                cast(amount as varchar),
                normalized_description
            )
        ) as duplicate_candidate_key,
        count(*) over (
            partition by
                account_slug,
                transaction_date,
                amount,
                normalized_description
        ) as duplicate_candidate_count,
        row_number() over (
            partition by transaction_id
            order by loaded_at desc, file_sha256 desc
        ) as transaction_id_rank
    from {{ ref('stg_raw_transactions') }} as transactions
)

select
    * exclude (transaction_id_rank),
    duplicate_candidate_count > 1 as is_duplicate_candidate
from ranked
where transaction_id_rank = 1
