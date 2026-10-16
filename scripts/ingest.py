#!/usr/bin/env python3
"""Ingest PDF statements into DuckDB raw tables using the Monopoly library (see docs/DECISIONS.md D1, D3).

Layout: <statements_dir>/<bank>/<account_slug>/<file>.pdf  (Monopoly leaves `account` null,
so the folder supplies it). Idempotent: files are keyed by sha256 and skipped once loaded ok.
Loads raw data only; no categorisation. Targets `sample` unless --target real is given.
"""
import argparse
import hashlib
import json
import os
import sys
import traceback
from pathlib import Path

import duckdb

DEFAULT_DB = {"sample": "data/sample/sample.duckdb", "real": "data/finance.duckdb"}
DB_ENV = {"sample": "FIN_SAMPLE_DUCKDB_PATH", "real": "FIN_DUCKDB_PATH"}


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_pdf(path: Path) -> dict:
    """Monopoly library -> versioned JSON envelope (dict). Keep all Monopoly calls in this function."""
    from monopoly.banks import BankDetector, banks
    from monopoly.generic import GenericBank
    from monopoly.pdf import PdfDocument, PdfParser
    from monopoly.pipeline import Pipeline
    from monopoly.serialize import statement_to_dict

    doc = PdfDocument(path)  # passwords come from PDF_PASSWORDS
    doc.unlock_document()
    bank = BankDetector(doc).detect_bank(banks) or GenericBank
    pipeline = Pipeline(PdfParser(bank, doc))
    statement = pipeline.extract()
    return statement_to_dict(statement, pipeline.transform(statement))


def init_db(con, schema: str) -> None:
    con.execute(f"create schema if not exists {schema}")
    con.execute(f"""create table if not exists {schema}.ingest_log (
        file_sha256 varchar primary key, source_file varchar, bank_folder varchar,
        account_slug varchar, status varchar, n_rows integer, error varchar, ingested_at timestamp)""")
    con.execute(f"""create table if not exists {schema}.raw_statements (
        file_sha256 varchar, source_file varchar, bank_folder varchar, account_slug varchar,
        monopoly_bank varchar, statement_type varchar, period_start date, period_end date,
        schema_version integer, payment_summary json, balances json, loaded_at timestamp)""")
    con.execute(f"""create table if not exists {schema}.raw_transactions (
        transaction_id varchar, file_sha256 varchar, source_file varchar, bank_folder varchar,
        account_slug varchar, transaction_date date, posting_date date, description varchar,
        amount double, currency varchar, direction varchar, balance double, loaded_at timestamp)""")


def save_json(data: dict, out_dir: Path, path: Path, sha: str, bank_folder: str, account: str) -> Path:
    """Keep the parsed envelope for debugging/reload: <out>/<bank>/<account>/<stem>.<sha8>.json (gitignored)."""
    dest = out_dir / bank_folder / account / f"{path.stem}.{sha[:8]}.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return dest


def load_one(con, schema, path, sha, bank_folder, account, out_dir):
    data = parse_pdf(path)
    save_json(data, out_dir, path, sha, bank_folder, account)
    txs = data["transactions"]
    con.execute("begin")
    try:
        con.execute(f"delete from {schema}.raw_transactions where file_sha256 = ?", [sha])
        con.execute(f"delete from {schema}.raw_statements where file_sha256 = ?", [sha])
        con.execute(
            f"insert into {schema}.raw_statements values (?,?,?,?,?,?,?,?,?,?,?,now())",
            [sha, str(path), bank_folder, account, data["bank"], data["statement_type"],
             data["period_start"], data["period_end"], data["schema_version"],
             json.dumps(data["payment_summary"]), json.dumps(data["balances"])],
        )
        if txs:
            con.executemany(
                f"insert into {schema}.raw_transactions values (?,?,?,?,?,?,?,?,?,?,?,?,now())",
                [[t["id"], sha, str(path), bank_folder, account, t["transaction_date"], t["posting_date"],
                  t["description"], t["amount"], t["currency"], t["direction"], t["balance"]] for t in txs],
            )
        con.execute("commit")
    except Exception:
        con.execute("rollback")
        raise
    return len(txs)


def log(con, schema, sha, path, bank_folder, account, status, n=0, error=None):
    con.execute(f"delete from {schema}.ingest_log where file_sha256 = ?", [sha])
    con.execute(f"insert into {schema}.ingest_log values (?,?,?,?,?,?,?,now())",
                [sha, str(path), bank_folder, account, status, n, error])


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--target", choices=["sample", "real"], default="sample")
    ap.add_argument("--statements-dir", default=os.environ.get("FIN_STATEMENTS_DIR", "statements"))
    ap.add_argument("--json-dir", default=os.environ.get("FIN_MONOPOLY_OUT_DIR", "data/monopoly_out"))
    ap.add_argument("--force", action="store_true", help="re-parse files already loaded ok")
    args = ap.parse_args()

    schema = os.environ.get("FIN_RAW_SCHEMA", "raw")
    db = os.environ.get(DB_ENV[args.target], DEFAULT_DB[args.target])
    root = Path(args.statements_dir)
    out_dir = Path(args.json_dir)
    Path(db).parent.mkdir(parents=True, exist_ok=True)
    con = duckdb.connect(db)
    init_db(con, schema)

    counts = {"ok": 0, "skipped": 0, "failed": 0, "misplaced": 0}
    for pdf in sorted(root.rglob("*.pdf")):
        rel = pdf.relative_to(root).parts
        if len(rel) != 3:
            print(f"MISPLACED (expected <bank>/<account>/file.pdf): {pdf}")
            counts["misplaced"] += 1
            continue
        bank_folder, account = rel[0], rel[1]
        sha = sha256_file(pdf)
        done = con.execute(f"select 1 from {schema}.ingest_log where file_sha256=? and status='ok'", [sha]).fetchone()
        if done and not args.force:
            counts["skipped"] += 1
            continue
        try:
            n = load_one(con, schema, pdf, sha, bank_folder, account, out_dir)
            log(con, schema, sha, pdf, bank_folder, account, "ok", n)
            counts["ok"] += 1
            print(f"ok      {pdf} ({n} rows)")
        except Exception as e:  # one bad PDF must not stop the batch
            log(con, schema, sha, pdf, bank_folder, account, "failed", error=f"{type(e).__name__}: {e}")
            counts["failed"] += 1
            print(f"FAILED  {pdf}: {type(e).__name__}: {e}")
            if os.environ.get("FIN_DEBUG"):
                traceback.print_exc()
    print(f"target={args.target} db={db} " + " ".join(f"{k}={v}" for k, v in counts.items()))
    return 1 if counts["failed"] or counts["misplaced"] else 0


if __name__ == "__main__":
    sys.exit(main())
