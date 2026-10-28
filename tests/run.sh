#!/usr/bin/env sh
# Runs the RUIN test suites against the addon folders in this repo.
# Needs a Lua 5.1 interpreter: set LUA=/path/to/lua5.1 if it isn't on PATH as lua5.1.
# Exits non-zero when any check fails or a suite stops early.
cd "$(dirname "$0")"
LUA="${LUA:-lua5.1}"
status=0
for t in run.lua run_modules.lua run_features.lua run_security.lua; do
  echo "== $t"
  out=$("$LUA" "$t" 2>&1) || status=1
  printf '%s\n' "$out" | grep -E "FAIL|passed|^       " || status=1
  if printf '%s\n' "$out" | grep -q "FAIL"; then status=1; fi
done
exit $status
