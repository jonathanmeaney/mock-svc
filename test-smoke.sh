#!/usr/bin/env bash
set -euo pipefail

: "${MOCK_HOST:=localhost}"
: "${ADMIN_PORT:=2525}"
: "${USER_PORT:=3101}"

QUIET=${QUIET:-0}

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_GREEN="\033[32m"; C_RED="\033[31m"; C_YELLOW="\033[33m"; C_CYAN="\033[36m"; C_RESET="\033[0m"; BOLD="\033[1m"
else
  C_GREEN=""; C_RED=""; C_YELLOW=""; C_CYAN=""; C_RESET=""; BOLD=""
fi

info(){ printf "%s%s%s\n" "$C_CYAN" "$1" "$C_RESET"; }
ok(){ printf "%s%s%s\n" "$C_GREEN" "$1" "$C_RESET"; }
warn(){ printf "%s%s%s\n" "$C_YELLOW" "$1" "$C_RESET"; }
err(){ printf "%s%s%s\n" "$C_RED" "$1" "$C_RESET"; }

log(){ [ "$QUIET" = 1 ] || printf "%s\n" "$1"; }
info(){ [ "$QUIET" = 1 ] || printf "%s%s%s\n" "$C_CYAN" "$1" "$C_RESET"; }
ok(){ [ "$QUIET" = 1 ] || printf "%s%s%s\n" "$C_GREEN" "$1" "$C_RESET"; }
warn(){ [ "$QUIET" = 1 ] || printf "%s%s%s\n" "$C_YELLOW" "$1" "$C_RESET"; }
err(){ printf "%s%s%s\n" "$C_RED" "$1" "$C_RESET"; }

info "Checking admin endpoint on $MOCK_HOST:$ADMIN_PORT ..."
retries=0
admin_ok=false
while [ $retries -lt 20 ]; do
  body=$(curl -s -m 2 http://$MOCK_HOST:$ADMIN_PORT/ || true)
  # Accept either legacy HTML containing 'mountebank' or JSON with _links.imposters
  if echo "$body" | grep -qi mountebank; then
    admin_ok=true; break
  fi
  if echo "$body" | grep -q '"_links"' && echo "$body" | grep -q 'imposters'; then
    admin_ok=true; break
  fi
  sleep 0.25; retries=$((retries+1))
done
if [ "$admin_ok" != true ]; then
  status=$(curl -s -o /dev/null -w "%{http_code}" http://$MOCK_HOST:$ADMIN_PORT/ || true)
  err "Admin readiness failed after $retries attempts (last status: $status). Partial body:"
  echo "$body" | head -n 20 >&2
  exit 1
fi

info "Checking sample stub (GET /users/42)..."
retries=0
stub_ok=false
while [ $retries -lt 12 ]; do
  resp=$(curl -s -o /dev/null -w "%{http_code}" http://$MOCK_HOST:$USER_PORT/users/42 || true)
  if [ "$resp" = "200" ]; then stub_ok=true; break; fi
  sleep 0.3; retries=$((retries+1))
done
if [ "$stub_ok" != true ]; then
  err "Stub check failed after $retries attempts (last status: $resp)"
  exit 1
fi

ok "All smoke tests passed."
