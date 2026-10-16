# personal-finance

Monthly snapshot of how your finances are tracking: income vs. spend, savings rate, spend by category, month-over-month trends, top merchants, and transactions that still need categorisation.

**Stack:** [Monopoly](https://github.com/benjamin-awd/monopoly) (PDF → structured transactions) → DuckDB → dbt Core → [dbt Charts](https://docs.getdbt.com/guides/dbt-charts) (YAML dashboards).

> Status: core MVP implemented. The project includes a committed synthetic PDF, ingestion, dbt models and tests, starter seeds, and one dbt Charts board.

## Privacy model

Real statements and data never leave your machine. `statements/`, Monopoly output, `*.duckdb`, `.env`, `profiles.yml` and `local_*.csv` are gitignored and blocked by pre-commit. The repo ships only generic starter seeds and synthetic sample data ([plan](docs/SAMPLE_DATA_PLAN.md)).

## Setup

1. Prereqs: [uv](https://docs.astral.sh/uv/), pipx, and for Monopoly `brew install gcc@11 pkg-config poppler ocrmypdf` (macOS).
2. `make setup`: creates `.venv` (Python 3.12), installs deps, copies `.env` and `profiles.yml` from the examples.
3. Monopoly is installed by `make setup` (pinned). Add the `ocr` extra yourself for scanned PDFs.
4. `make hooks`: installs pre-commit (needs a git repo).
5. Edit `.env` (currency, paths). Nothing user-specific is hardcoded.

## Workflow

| Step | Command |
|---|---|
| Drop PDFs in `statements/<bank>/<account_slug>/` | n/a |
| Parse PDFs and load raw tables | `make ingest TARGET=real` |
| Load the committed synthetic statement | `make sample-ingest` |
| Build sample models | `make seed && make build` |
| Dashboards | `make charts`, then open the printed URL |

`TARGET` defaults to `sample`. Using real data is always an explicit `TARGET=real`.

Note: dbt Charts opens DuckDB read-only, so stop `dbt` before `dct serve` (and the DB file must already exist).

## Seeds: shipped vs. local

- **Shipped** seeds (`seeds/*.csv`) are generic starters: taxonomy, merchant aliases, rules, accounts, and transaction overrides.
- **Local** equivalents (`seeds/local_*.csv`, gitignored) hold your own rows. Templates live in `templates/local_*.example.csv`; `make init-local` copies them without overwriting.
- dbt unions the two, **local rows win** on conflicting keys.
- Set `enable_local_seeds: true` in your local dbt vars after running `make init-local`.
- Account slugs are stable, non-sensitive identifiers from `statements/<bank>/<account_slug>/`; never use card or account numbers.

## Reporting behavior

- Categorisation precedence is transaction override → category rule → merchant alias → Uncategorised.
- Transfers and uncategorised rows remain visible in `fct_transactions` but are excluded from income and spend measures.
- Duplicate-looking rows are flagged for review; only repeated `transaction_id` values are deduplicated automatically.
- Reporting remains currency-specific. The project does not convert or aggregate different currencies into a base currency.

## Dashboards

- `charts/overview.yml`: a single page for monthly cash flow, category spend mix, top-ten merchants, categorisation coverage, and the uncategorised review queue. Part-to-whole charts and the merchant ranking use the most active currency so values from different currencies are never summed together.

## Layout

```
models/{staging,intermediate,marts}/   dbt models, properties, and unit tests
seeds/                                 starter taxonomy, aliases, rules, accounts, overrides
macros/                                shared SQL normalization
scripts/                               ingest.py (Monopoly library -> DuckDB), pre-commit checks
statements/                            your PDFs (gitignored)
charts/                                one dbt Charts board
templates/                             local_*.example.csv templates
data/sample/                           committed synthetic PDF and local DuckDB
docs/                                  decisions, implementation plan, sample-data status
```

## Deferred

Budget-vs-actual reporting can be added later with a monthly budget seed, an additive `fct_budget_vs_actual` mart, and another section on the board. Refund linkage, paired-leg transfer detection, and P2P counterparty classification are also outside the core MVP.
