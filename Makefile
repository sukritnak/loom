SHELL := /bin/bash
CFG   := node tools/cfg.js
DASH  := $(shell $(CFG) get dashboard)
DASH  := $(if $(DASH),$(DASH),agent-dashboard)

# Optionally target a single service:  make scaffold SVC=web   /   make dev SVC=api
SVC ?=

# emit "id\tside\tRESOLVED_PATH\tstack" lines, filtered by SVC if given
define SERVICES
$(CFG) resolved | { if [ -n "$(SVC)" ]; then awk -F'\t' -v id="$(SVC)" '$$1==id'; else cat; fi; }
endef

.DEFAULT_GOAL := help
.PHONY: help loop-start list-project deploy new-project start set-base setup verify config init scaffold dev build test lint \
        docker-build docker-up docker-down dashboard status reset-status loop

help: ## show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	  awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-14s\033[0m %s\n",$$1,$$2}'

loop-start: ## (blueprint) START HERE — guided wizard: deploy? → base → new/existing → run
	@bash tools/loop-start.sh

list-project: ## (blueprint) list all projects created under the base folder
	@bash tools/start-loop-orch.sh --list

deploy: ## (blueprint) install the agent team into Claude Code + Hermes — run once
	@bash tools/deploy.sh

new-project: ## (blueprint) create a real project at ~/Documents/coding/agent-build (NAME=...)
	@bash tools/new-project.sh $(NAME)

start: ## (blueprint) point loop-orch at a project (create if missing) — [NAME=...]
	@bash tools/start-loop-orch.sh $(NAME)

set-base: ## (blueprint) set your default folder for new projects (DIR=/path, must be absolute & outside this repo)
	@[ -n "$(DIR)" ] || { echo "usage: make set-base DIR=/path/to/projects"; exit 1; }
	@r="$$(bash tools/base-dir.sh "$(DIR)")" && printf '%s\n' "$$r" > .base-dir && echo "default base dir → $$r"

setup: ## interactive wizard → writes loop.config.json (asks step by step)
	@bash tools/init-config.sh

verify: ## check folders exist + access (existing) / prepare base_dir (new)
	@bash tools/verify-paths.sh

config: ## list project + all services (resolved absolute paths)
	@echo "project=$(shell $(CFG) get project)  mode=$(shell $(CFG) get mode)  autonomy=$(shell $(CFG) get autonomy)"
	@printf "%-10s %-4s %-40s %s\n" ID SIDE RESOLVED-PATH STACK
	@$(CFG) resolved | awk -F'\t' '{printf "%-10s %-4s %-40s %s\n",$$1,$$2,$$3,$$4}'

init: verify scaffold ## verify access then scaffold ALL services
	@echo "init complete"

scaffold: ## scaffold service(s): make scaffold [SVC=id]
	@$(SERVICES) | while IFS=$$'\t' read -r id side path stack; do \
	  [ -z "$$id" ] && continue; \
	  echo "── $$id ($$side) → $$path [$$stack]"; \
	  bash tools/scaffold.sh "$$side" "$$path" "$$stack"; \
	done

dev: ## run dev server for one service: make dev SVC=api
	@[ -n "$(SVC)" ] || { echo "usage: make dev SVC=<id>  (ids: $(shell $(CFG) ids))"; exit 1; }
	@p=$$($(CFG) abspath "$(SVC)"); [ -n "$$p" ] || { echo "unknown service $(SVC)"; exit 1; }; \
	  cd "$$p" && ( $(MAKE) dev 2>/dev/null || npm run dev 2>/dev/null || \
	  ( [ -x .venv/bin/uvicorn ] && .venv/bin/uvicorn src.main:app --reload ) || echo "set a dev command in $$p" )

build: ## build all services
	@$(SERVICES) | while IFS=$$'\t' read -r id side path stack; do \
	  [ -z "$$id" ] && continue; echo "build $$id"; \
	  ( cd "$$path" && (npm run build 2>/dev/null || true) ); done

test: ## test all services
	@$(SERVICES) | while IFS=$$'\t' read -r id side path stack; do \
	  [ -z "$$id" ] && continue; echo "test $$id"; \
	  ( cd "$$path" && (npm test 2>/dev/null || (.venv/bin/pytest 2>/dev/null || true)) ); done

lint: ## lint all services
	@$(SERVICES) | while IFS=$$'\t' read -r id side path stack; do \
	  [ -z "$$id" ] && continue; ( cd "$$path" && (npm run lint 2>/dev/null || true) ); done

docker-build: ## build images for BE services (or one with SVC=id)
	@$(CFG) resolved be | { if [ -n "$(SVC)" ]; then awk -F'\t' -v id="$(SVC)" '$$1==id'; else cat; fi; } | \
	  while IFS=$$'\t' read -r id side path stack; do \
	  [ -z "$$id" ] && continue; echo "docker build $$id"; \
	  ( cd "$$path" && docker build -t "$(shell $(CFG) get project)-$$id" . ); done

docker-up: ## docker compose up for BE services (or one with SVC=id)
	@$(CFG) resolved be | { if [ -n "$(SVC)" ]; then awk -F'\t' -v id="$(SVC)" '$$1==id'; else cat; fi; } | \
	  while IFS=$$'\t' read -r id side path stack; do \
	  [ -z "$$id" ] && continue; ( cd "$$path" && docker compose up -d ); done

docker-down: ## docker compose down for BE services
	@$(CFG) services be | while IFS=$$'\t' read -r id side path stack; do \
	  [ -z "$$id" ] && continue; ( cd "$$path" && docker compose down ); done

dashboard: ## open the live agent dashboard
	@bash "$(DASH)/serve.sh"

status: ## print current loop status.json
	@cat "$(DASH)/status.json" 2>/dev/null || echo "no status yet — run a loop first"

reset-status: ## clear the dashboard status
	@node "$(DASH)/agent-status.js" reset ""

loop: ## print the Claude Code command to run the loop (TASK="...")
	@echo 'In Claude Code, run:'
	@echo '  Use loop-orch at $(shell $(CFG) get autonomy): $(or $(TASK),<describe the feature/bug>)'
	@echo '  (it reads loop.config.json — services: $(shell $(CFG) ids))'
