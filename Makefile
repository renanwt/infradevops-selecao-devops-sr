# ---------------------------------------------------------------------------
# Makefile - atalhos de desenvolvimento
# Uso: make <alvo>   (make help lista os alvos)
# ---------------------------------------------------------------------------
.DEFAULT_GOAL := help
SHELL := /bin/sh

PYTHON  ?= python
VENV    ?= .venv
ifeq ($(OS),Windows_NT)
  BIN := $(VENV)/Scripts
else
  BIN := $(VENV)/bin
endif
PIP     := $(BIN)/pip
APP     := app.main:app
IMAGE   ?= comments-api
TAG     ?= dev

.PHONY: help venv install dev lint fmt typecheck test run db-up db-down migrate docker-build docker-run clean

help: ## Lista os alvos disponiveis
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

venv: ## Cria o virtualenv
	$(PYTHON) -m venv $(VENV)
	$(PIP) install --upgrade pip

install: venv ## Instala dependencias de runtime + dev
	$(PIP) install -e ".[dev]"

dev: install ## Prepara ambiente completo (deps + pre-commit)
	$(BIN)/pre-commit install

lint: ## Ruff (lint) sem alterar arquivos
	$(BIN)/ruff check .
	$(BIN)/ruff format --check .

fmt: ## Ruff: corrige e formata
	$(BIN)/ruff check --fix .
	$(BIN)/ruff format .

typecheck: ## mypy strict em app/
	$(BIN)/mypy

test: ## Todos os testes com cobertura
	$(BIN)/pytest

run: ## Sobe a API local com reload
	$(BIN)/uvicorn $(APP) --host 0.0.0.0 --port 8000 --reload

db-up: ## Sobe Postgres local via docker compose
	docker compose up -d postgres

db-down: ## Derruba Postgres local
	docker compose down -v

migrate: ## Aplica migracoes Alembic
	$(BIN)/alembic -c app/alembic.ini upgrade head

docker-build: ## Build da imagem
	docker build -t $(IMAGE):$(TAG) .

docker-run: ## Roda a imagem localmente
	docker run --rm -p 8000:8000 --env-file .env $(IMAGE):$(TAG)

clean: ## Remove artefatos
	rm -rf $(VENV) .pytest_cache .mypy_cache .ruff_cache .coverage htmlcov dist build *.egg-info
	find . -type d -name __pycache__ -exec rm -rf {} +
