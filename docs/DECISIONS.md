# Decision log

Short records of decisions and why, so later readers (and the model brainstorm) can see the reasoning. Newest last. Status: Accepted unless noted.

## D1. Loader consumes Monopoly JSON, not CSV (2026-10-16)
- **Context:** The CSV sample (`Date, Description, Amount, Bank`) has a signed amount but no account, currency, direction or stable id. Monopoly's `--format json` adds a stable per-transaction `id`, currency, posting_date and direction. `account` is `null` in both.
- **Decision:** Use `--format json`; the loader flattens it to rows and adds `account_slug` (from `statements/<bank>/<account_slug>/`) and `source_file`.
- **Why:** A stable id is the key that per-transaction overrides depend on, and currency/direction remove sign guessing.
- **Consequences / follow-ups:** Verify the id is stable across re-runs and overlapping statements; if not, fall back to a hash (bank, account, date, amount, description, occurrence index). Schema is versioned, so pin a Monopoly version.

## D2. PayNow person-to-person (P2P) defaults to uncategorised, classified via a local counterparties seed (2026-10-16)
- **Context:** A P2P payment can be a transfer, real spend (rent, shared bill), or income/reimbursement, and the statement text (just a person's name) cannot say which. Options considered: (1) by sign as spend/income, (2) all `is_transfer`, (3) uncategorised, (4) counterparty seed, (5) net by counterparty per month, (6) reimbursement category, (7) amount/direction heuristics.
- **Decision:** Combine (3) and (4). A P2P row with no matching counterparty rule is Uncategorised and **never silently counted** as income, spend or transfer. A counterparty, once classified in `local_counterparties.csv` (name → category/subcategory or `is_transfer`), applies to all its transactions.
- **Why:**
  - (1) and (2) are silently wrong in the common case (reimbursements inflate income and spend; real rent disappears).
  - (3) is the honest default and reuses the uncategorised page we already need as the feedback loop.
  - (4) makes one decision per person instead of per transaction and fits the aliases/rules/overrides layering.
  - Names are PII, so the counterparties seed is `local_*` only and gitignored; the shipped starter contains no names.
- **Rejected for now:** (5) netting and (6) reimbursement linking add pairing windows/tolerances and complexity before the basics work; (7) heuristics are too fragile to assign categories, only to suggest them (possible input to the optional suggestions CSV).
- **Deferred:** (5) netting by counterparty within a month, to be revisited once core categorisation and the uncategorised page work. Related open questions: PLAN.md Q5 (transfer detection) and Q6 (refund linkage).
- **Consequences:** Needs a P2P detection rule (description pattern such as `PAYNOW`/`FAST` to a person) feeding a normalised counterparty name; name normalisation must strip reference numbers and case differences. Budget/summary figures exclude uncategorised P2P until classified, so the dashboard should show the uncategorised total prominently.

## D3. Parse via Monopoly's Python library and get JSON in-process (2026-10-16)
- **Context:** Question was whether the library, not the CLI, can return JSON. Tested with `monopoly-core` 0.23.2 (Python 3.12 venv, scratchpad) on the package's bundled example PDF.
- **Finding:** Yes. `monopoly.serialize.statement_to_dict(statement, transactions)` returns the versioned JSON envelope (schema_version 2: bank, statement_type, period_start/end, payment_summary, balances, transactions[id, transaction_date, posting_date, description, amount, currency, account, balance, direction]) as a plain dict, no file needed. 52 rows parsed; ids identical across two parses of the same file. `Pipeline.load(..., format_type="json")` also writes a file.
- **Decision:** The loader calls the library directly, mirroring the CLI's flow (`PdfDocument` → `unlock_document` → `BankDetector.detect_bank(banks) or GenericBank` → `PdfParser` → `Pipeline.extract/transform` → `statement_to_dict`), wrapped in try/except per file, and inserts rows without writing intermediate JSON.
- **Why:** No subprocess, structured errors per file, no temp files, bank detection included.
- **Risks:** `statement_to_dict` and `Pipeline` are not documented public API (the docs show only the CLI), so pin the version and keep the calls in one module. Id stability was only shown for repeated parses of one file; cross-statement stability for overlapping periods is explicitly *not guaranteed* by Monopoly (see `assign_ids` docstring), so staging still needs dedupe handling. Real banks, passwords and OCR paths are untested.
