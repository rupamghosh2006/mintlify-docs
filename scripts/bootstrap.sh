#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { printf "${GREEN}✔${NC}  %s\n" "$1"; }
warn()  { printf "${YELLOW}⚠${NC}  %s\n" "$1"; }
error() { printf "${RED}✖${NC}  %s\n" "$1"; }

cd "$PROJECT_ROOT"

# ── Prerequisites ──────────────────────────────────────────────────────────────

printf "\n%s\n" "── Checking prerequisites ──"

if ! command -v node >/dev/null 2>&1; then
  error "node is not installed. Install Node.js >= 18: https://nodejs.org/"
  exit 1
fi

NODE_VERSION="$(node -v | sed 's/^v//')"
NODE_MAJOR="${NODE_VERSION%%.*}"
if [ "$NODE_MAJOR" -lt 18 ]; then
  error "Node.js >= 18 is required (found v${NODE_VERSION})."
  exit 1
fi
info "node v${NODE_VERSION}"

# Check for pnpm (preferred) or npm
if command -v pnpm >/dev/null 2>&1; then
  info "pnpm $(pnpm -v)"
  PKG_MANAGER="pnpm"
elif command -v npm >/dev/null 2>&1; then
  warn "pnpm not found — falling back to npm $(npm -v)"
  warn "Install pnpm for best results: npm install -g pnpm"
  PKG_MANAGER="npm"
else
  error "Neither pnpm nor npm is installed."
  exit 1
fi

# ── Install dependencies ───────────────────────────────────────────────────────

printf "\n%s\n" "── Installing dependencies ──"

if [ "$PKG_MANAGER" = "pnpm" ]; then
  pnpm install
else
  npm install
fi
info "Dependencies installed"

# ── Next steps ─────────────────────────────────────────────────────────────────

printf "\n%s\n" "── Next steps ──"
echo ""
echo "  1. Start the dev server:"
echo "       make dev"
echo ""
echo "  2. Open the local preview in your browser (default: http://localhost:3000)"
echo ""
echo "  3. Edit .mdx files to update documentation content."
echo "     Navigation is configured in docs.json."
echo ""
info "Bootstrap complete!"
