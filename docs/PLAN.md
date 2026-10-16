# Plan: personal-finance analytics

Decisions and rationale are logged in [DECISIONS.md](DECISIONS.md) (D1 JSON ingest, D2 PayNow P2P handling).

This document began as the model-design brainstorm. The core MVP is now implemented; remaining items are retained as roadmap context.

## 1. Goal and scope
Monthly snapshot: income vs. spend, savings rate, spend by category, MoM trends, top merchants, and uncategorised activity. Shareable on GitHub: no hardcoded private paths, accounts, categories, or real financial data.

Budget-vs-actual was removed from the core MVP and can be added later without changing the existing transaction facts.

## 2. Tooling verification

### Monopoly (PDF → CSV)
- PyPI `monopoly-core`, install via pipx; needs poppler (`brew install gcc@11 pkg-config poppler ocrmypdf`); optional `[ocr]` extra.
- Supported (README as of 2026-10): credit + debit: Bank of America, BMO, CIBC, DBS/POSB, Maybank, OCBC, RBC, Scotiabank, TD, UOB. Credit only: Canadian Tire Bank, Capital One CA, Chase, Citibank, HSBC, Standard Chartered, Trust, US Bank. Debit only: Schwab, Zürcher Kantonalbank. "Every supported bank" = this list, which changes over time; the repo should not hardcode it.
- Default CSV is 4 columns (names not documented). `--format json` adds statement metadata and a stable per-transaction `id`, currency, posting_date, direction. `account` is currently `null`. **Account must therefore come from our folder convention** (`statements/<bank>/<account_slug>/`).
- Encrypted PDFs: `PDF_PASSWORDS` env var.
- Not tested here: no real statements are used. Parsing accuracy per bank is unverified.

### dbt Charts (dashboards)
Verified locally against DuckDB in a throwaway project (outside this repo), `dct 0.9.1`, dbt-core 1.12.6, dbt-duckdb, Python 3.12:
- `uv tool install dbt-charts` / `pip install dbt-charts`; `dct validate`, `dct serve` (hot reload), `dct render --format html` all work with a `dbt_profile` source on DuckDB. Server started (HTTP 200); HTML render succeeded.
- Gotchas found:
  - `dct` opens DuckDB **read-only** and the file must already exist → can't serve while `dbt` holds the write lock; run sequentially.
  - Boards must live in `charts/` (quickstart convention), so the requested `dashboards/` folder is named `charts/`. Not verified whether this is configurable.
  - `dbt_charts.yml` accepts a fixed key set (`sources`, `server`, …); no `name`.
  - Queries are raw SQL against `schema.table`, so mart schema names (`<target schema>_marts`, given our `+schema` config) must be written into board SQL or aligned via a schema-name macro. Brainstorm item.
  - Quickstart is written for dbt 1.12+/v2; v1 adapter still needed.
  - Young project (0.x): expect syntax churn; pin the version. Secondary reports say some chart types (sankey, funnel, gauge) are unsupported; unverified.
- Fallback **not needed**. If the project stalls, Evidence.dev (Markdown+SQL, DuckDB-native, static site, mature) is the fallback; cost is a Node toolchain and a second dashboard format.
- Not yet tested: multi-row layouts with real marts, variables/filters (month picker), uncategorised page.

## 3. Implemented model layers
- **raw** (loaded by `scripts/load_duckdb.py`): `raw_transactions` + source_file, loaded_at, bank, account_slug.
- **staging**: one model per source shape; typed, sign-normalised, `transaction_id` generated; seed unions (`stg_*` for shipped + local with local priority).
- **intermediate**:
  1. merchant normalisation (C): raw description → merchant via aliases seed.
  2. categorisation: rules (A) by priority, then overrides (B) by `transaction_id`; resolves to category/subcategory/is_transfer; suggestions CSV (optional, later).
  3. transfer/CC-payment detection (rules + paired-leg matching across accounts).
  4. refund/reversal linkage to the original transaction.
- **marts**: `fct_transactions` (grain: transaction), `fct_monthly_summary` (income, spend, net, savings rate), `fct_monthly_category`, `fct_top_merchants`, `rpt_uncategorised`.
- **seeds** (shipped + `local_*` equivalents): taxonomy (category→subcategory), merchant_aliases, category_rules, budgets, accounts (metadata), and `transaction_overrides` (local only is plausible: it's inherently personal).
- **charts**: one board with Overview, Categories, Merchants, and Uncategorised sections.

## 4. Design constraints carried in
- Local-over-shipped seed union, local rows win (define the key per seed).
- Two-level taxonomy. `is_transfer` first-class, excluded from income/spend. Refunds net against the original category. Uncategorised surfaced in its own model and page.
- Categorisation precedence proposal: override (B) > rule (A, by priority, then specificity) > alias default category (C) > Uncategorised.

## 5. Open questions
1. ~~Monopoly output shape~~ **Partly answered by a user-supplied sample** (Streamlit download, UOB debit account): CSV with columns `Date, Description, Amount, Bank`. Observations:
   - Amount is **signed** (debits negative, credits positive); no direction column, no currency, no account, no stable id. Bank is title-cased (`Uob`).
   - So `transaction_id` must be a hash (bank, account, date, amount, description, occurrence index), and account must come from the folder convention (the CSV can't supply it). The loader must add `account_slug`, `source_file`.
   - Descriptions are noisy and **contain PII**: full card numbers in card bill payments, person names in PayNow transfers, masked card digits (`xxxxxx1105`), reference numbers. Normalisation should strip digits/refs; PII scan and gitignore matter; sample data must not copy these.
   - Obvious transfer/payment patterns exist: `Bill Payment ... Cards`, `Funds Trf - FAST ... Trust Account`, PayNow to individuals (ambiguous: transfer vs. spend vs. income), GIRO collections (insurance, tax), salary via `GIRO SALA`, interest credits.
   - **Decision: loader uses Monopoly `--format json`** (stable id, currency, direction); the loader flattens it to rows. Verify id stability across re-runs before relying on it for overrides.
   - (superseded) does the JSON format (stable id, currency) beat this CSV? Is one row per day order stable across re-runs?
2. `transaction_id` definition: Monopoly id if stable across re-runs, else hash(bank, account, date, amount, description, occurrence index). Must survive re-ingesting overlapping statements.
3. Seed priority mechanics: union key per seed; how to express "delete/disable a shipped row" locally (tombstone column?).
4. Rule `match_type` vocabulary (exact/contains/starts_with/regex?) and case/whitespace normalisation; DuckDB regex dialect portability.
5. Transfer detection: rule-based only, or also leg-matching (equal/opposite amount, ±N days, different accounts)? What about transfers to an account not in the data?
6. Refund linkage: how to find the "original" (merchant + amount + window, or explicit override)? Cross-month refunds: net in refund month or restate original month?
7. Multi-currency: single base currency (`FIN_BASE_CURRENCY`) with FX seed, or per-currency reporting only? Monopoly foreign-currency extraction is "planned", not shipped.
8. Income definition: credits not marked transfer/refund; how to classify interest, reimbursements, dividends?
9. Budgets: deferred until after the core MVP. The intended additive design is monthly rows by currency, category, and optional subcategory.
10. Credit-card statement periods vs. calendar months (post date vs. transaction date)?
11. Schema/naming: how board SQL references marts given `+schema` prefixing in dbt-duckdb; add a `generate_schema_name` override?
12. Dashboards folder: `charts/` forced by dct; acceptable? Pin which `dbt-charts` version?
13. Real-vs-sample data: one DuckDB file per target (current) or schemas in one file?
14. LLM suggestions: scope, privacy (local model vs API; sending merchant strings only?), output CSV format for manual approval.
15. Python 3.12 pin vs. system 3.14 (dbt-duckdb support on 3.14 unverified).

## 6. Proposed build order
1. Settle open Qs 1 to 3, 11 (ingest contract, ids, seed union, schema naming).
2. Sample-data generator ([SAMPLE_DATA_PLAN.md](SAMPLE_DATA_PLAN.md)) and loader, so everything is testable without real data.
3. Staging + seed unions + tests (uniqueness of `transaction_id`, accepted values).
4. Taxonomy, aliases, rules; categorisation (C → A → B); uncategorised model.
5. Transfers, then refunds/reversals.
6. Marts: transactions, monthly summary, category, merchants. **Done for core MVP.**
7. A dbt Charts board with Overview, Categories, Merchants, and Uncategorised sections. **Done for core MVP.**
8. Local seed templates, `make init-local`, docs polish; run against real data last (`TARGET=real`, explicit).
9. Optional: LLM suggestions CSV.

## 7. Risks
| Risk | Mitigation |
|---|---|
| Real data/PII committed | gitignore + pre-commit file-block + PII scan; no git history yet, install hooks right after `git init` |
| Monopoly misparses a bank layout | row-count/balance reconciliation test per statement; manual spot check |
| Unstable `transaction_id` breaks overrides | decide Q2 early, test re-ingest idempotency |
| Double counting (transfers, CC payments, refunds) | `is_transfer` tests; reconcile spend to statement totals |
| dbt Charts is 0.x, syntax may change | pin version; Evidence.dev fallback |
| DuckDB single-writer lock vs. `dct serve` | sequential Make targets; documented |
| Rules grow unmaintainable | priority + tests for rule conflicts; rpt_uncategorised drives rule additions |
| Accidentally building against real DB | `TARGET` defaults to `sample`; real is explicit |
| Python 3.14 compat | venv pinned to 3.12 |

## 8. Deferred after the core MVP
- Budget-vs-actual inputs, mart, and dashboard.
- Refund and reversal linkage.
- Paired-leg transfer detection.
- P2P counterparty classification.
- Dedicated category, account, and merchant dimensions.
- Broader multi-month synthetic sample generation.
