with transactions as (
    select * from {{ ref('int_transactions_deduplicated') }}
),

aliases as (
    select * from {{ ref('int_merchant_aliases') }}
),

rules as (
    select * from {{ ref('int_category_rules') }}
),

taxonomy as (
    select * from {{ ref('int_taxonomy') }}
),

overrides as (
    select * from {{ ref('int_transaction_overrides') }}
),

alias_candidates as (
    select
        transactions.transaction_id,
        aliases.alias_key,
        aliases.merchant_name,
        aliases.taxonomy_key,
        row_number() over (
            partition by transactions.transaction_id
            order by
                case aliases.match_type when 'exact' then 0 else 1 end,
                aliases.alias_key
        ) as match_rank
    from transactions
    inner join aliases
        on (
            aliases.match_type = 'exact'
            and transactions.normalized_description = aliases.match_value
        )
        or (
            aliases.match_type = 'contains'
            and contains(transactions.normalized_description, aliases.match_value)
        )
),

best_alias as (
    select * exclude (match_rank)
    from alias_candidates
    where match_rank = 1
),

rule_candidates as (
    select
        transactions.transaction_id,
        rules.rule_key,
        rules.taxonomy_key,
        rules.is_transfer,
        row_number() over (
            partition by transactions.transaction_id
            order by
                rules.priority desc,
                case rules.match_type when 'exact' then 0 else 1 end,
                rules.rule_key
        ) as match_rank
    from transactions
    inner join rules
        on (
            rules.match_type = 'exact'
            and transactions.normalized_description = rules.match_value
        )
        or (
            rules.match_type = 'contains'
            and contains(transactions.normalized_description, rules.match_value)
        )
),

best_rule as (
    select * exclude (match_rank)
    from rule_candidates
    where match_rank = 1
),

resolved as (
    select
        transactions.*,
        coalesce(overrides.merchant_name, best_alias.merchant_name, transactions.description) as merchant_name,
        coalesce(
            overrides.category,
            rule_taxonomy.category,
            alias_taxonomy.category,
            '{{ var("uncategorised_label") }}'
        ) as category,
        coalesce(
            overrides.subcategory,
            rule_taxonomy.subcategory,
            alias_taxonomy.subcategory,
            '{{ var("uncategorised_label") }}'
        ) as subcategory,
        coalesce(overrides.is_transfer, best_rule.is_transfer, false) as is_transfer,
        case
            when overrides.transaction_id is not null then 'override'
            when best_rule.rule_key is not null then 'rule'
            when best_alias.alias_key is not null then 'alias'
            else 'uncategorised'
        end as categorisation_method,
        coalesce(
            best_rule.rule_key,
            best_alias.alias_key
        ) as categorisation_key
    from transactions
    left join overrides
        on transactions.transaction_id = overrides.transaction_id
    left join best_alias
        on transactions.transaction_id = best_alias.transaction_id
    left join best_rule
        on transactions.transaction_id = best_rule.transaction_id
    left join taxonomy as rule_taxonomy
        on best_rule.taxonomy_key = rule_taxonomy.taxonomy_key
    left join taxonomy as alias_taxonomy
        on best_alias.taxonomy_key = alias_taxonomy.taxonomy_key
)

select * from resolved
