#!/usr/bin/env python3
"""Pre-commit: fail if a staged path looks like real financial data or secrets."""
import re
import sys

BLOCKED = [
    r"(^|/)statements/(?!\.gitkeep$)",
    r"\.pdf$",
    r"\.duckdb(\.wal)?$",
    r"(^|/)\.env($|\.(?!example$))",
    r"(^|/)local_(?!.*\.example\.csv$).*\.csv$",
    r"(^|/)data/monopoly_out/",
    r"(^|/)profiles\.yml$",
]

# The one committed synthetic statement (Monopoly's bundled example). Exact paths only.
ALLOWED = {"data/sample/statements/example_bank/example_account/example_statement.pdf"}


def main(paths):
    bad = [p for p in paths if p not in ALLOWED and any(re.search(rx, p) for rx in BLOCKED)]
    for p in bad:
        print(f"BLOCKED (private/real data): {p}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
