#!/usr/bin/env python3
"""Pre-commit: heuristic PII scan (card numbers via Luhn, IBANs, emails, long account numbers).

Allowlist a line with the marker `pii-ok`. Heuristics only; not a guarantee.
"""
import re
import sys

CARD = re.compile(r"\b(?:\d[ -]?){13,19}\b")
IBAN = re.compile(r"\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b")
EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")
ACCT = re.compile(r"\b\d{9,12}\b")


def luhn(s):
    d = [int(c) for c in re.sub(r"\D", "", s)][::-1]
    if not 13 <= len(d) <= 19:
        return False
    t = sum(d[0::2]) + sum(sum(divmod(x * 2, 10)) for x in d[1::2])
    return t % 10 == 0


def main(paths):
    hits = 0
    for p in paths:
        try:
            lines = open(p, encoding="utf-8", errors="ignore").read().splitlines()
        except OSError:
            continue
        for n, line in enumerate(lines, 1):
            if "pii-ok" in line:
                continue
            found = []
            if any(luhn(m.group()) for m in CARD.finditer(line)):
                found.append("card-number")
            if IBAN.search(line):
                found.append("iban")
            if EMAIL.search(line):
                found.append("email")
            if ACCT.search(line) and p.endswith(".csv"):
                found.append("long-number")
            if found:
                hits += 1
                print(f"{p}:{n}: possible PII ({', '.join(found)})")
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
