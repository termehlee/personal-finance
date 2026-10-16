SHELL := /bin/bash
# sample | real. Always defaults to sample.
TARGET ?= sample
-include .env
export

.PHONY: help sample-ingest setup init-local hooks ingest build seed charts charts-validate clean

help:
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  %-16s %s\n", $$1, $$2}'

setup: ## Create venv (py3.12) and install deps
	uv venv --python 3.12 .venv && uv pip install -r requirements.txt
	@[ -f .env ] || cp .env.example .env
	@[ -f profiles.yml ] || cp profiles.yml.example profiles.yml

init-local: ## Copy templates/local_*.example.csv -> seeds/local_*.csv (never overwrites)
	@for f in templates/local_*.example.csv; do \
	  [ -e "$$f" ] || continue; t=seeds/$$(basename $$f .example.csv).csv; \
	  [ -e "$$t" ] || cp "$$f" "$$t"; done

hooks: ## Install pre-commit hooks (requires git repo)
	.venv/bin/pre-commit install

ingest: ## Parse PDFs in statements/ with Monopoly and load raw tables (TARGET=sample by default)
	.venv/bin/python scripts/ingest.py --target $(TARGET)

sample-ingest: ## Ingest the committed synthetic example PDF into the sample DB
	.venv/bin/python scripts/ingest.py --target sample --statements-dir data/sample/statements

seed: ## dbt seed
	.venv/bin/dbt seed --target $(TARGET)

build: ## dbt build (TARGET=sample by default; real data needs TARGET=real explicitly)
	.venv/bin/dbt build --target $(TARGET)

charts-validate: ## Validate dbt Charts boards
	.venv/bin/dct validate

charts: ## Serve dbt Charts locally (DuckDB opened read-only: don't run dbt at the same time)
	.venv/bin/dct serve

clean:
	rm -rf target logs renders
