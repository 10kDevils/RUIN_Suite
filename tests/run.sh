#!/usr/bin/env sh
# Runs the RUIN test suites against the addon folders in this repo.
# Needs a Lua 5.1 interpreter: set LUA=/path/to/lua5.1 if it isn't on PATH as lua5.1.
set -e
cd "$(dirname "$0")"
LUA="${LUA:-lua5.1}"
status=0
for t in run.lua run_modules.lua run_features.lua; do
  echo "== $t"
  "$LUA" "$t" | grep -E "FAIL|passed|^       " || status=1
done
exit $status
