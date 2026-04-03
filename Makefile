.DEFAULT_GOAL := help

# Auto-detect pnpm (preferred) or fall back to npx/npm
PKG_RUN := $(shell command -v pnpm >/dev/null 2>&1 && echo "pnpm" || echo "npx")
PKG_INSTALL := $(shell command -v pnpm >/dev/null 2>&1 && echo "pnpm install" || echo "npm install")

.PHONY: help bootstrap install dev build clean

help: ## Show available targets
	@printf "\nUsage: make <target>\n\n"
	@printf "Targets:\n"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""

bootstrap: ## Zero-to-running setup (install deps, print next steps)
	@bash scripts/bootstrap.sh

install: ## Install dependencies
	$(PKG_INSTALL)

dev: ## Start Mintlify dev server (http://localhost:3000)
	$(PKG_RUN) mintlify dev

build: ## Validate the documentation build
	$(PKG_RUN) mintlify validate

clean: ## Remove node_modules and Mintlify cache
	rm -rf node_modules/ .mintlify/
