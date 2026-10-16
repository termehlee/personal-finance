# Synthetic sample data status

Purpose: let anyone clone the repo, ingest a synthetic statement, build the dbt project, and open dashboards without using real financial data.

## Current sample

- Input: `data/sample/statements/example_bank/example_account/example_statement.pdf`.
- Loader: `make sample-ingest`.
- Output: `data/sample/sample.duckdb`, which stays local and is gitignored.
- Current coverage: 52 unique transactions from July 2023 with debit and credit directions.
- Currency is absent from this Monopoly sample and falls back to the `example_account` seed currency.
- Re-running ingestion is idempotent because the statement file hash is already recorded.

## Reproducible workflow

```sh
make setup
make sample-ingest
make seed
make build
make charts
```

The sample PDF proves the end-to-end Monopoly → DuckDB → dbt path. Static dbt unit tests cover categorisation precedence, rule priority, and reporting exclusions that the single statement cannot represent comprehensively.

## Future sample expansion

A broader generated fixture can later add multiple months and accounts, refunds, overlapping statements, foreign currencies, P2P transfers, local-seed overrides, and budget scenarios. That expansion is not required for the core MVP.
