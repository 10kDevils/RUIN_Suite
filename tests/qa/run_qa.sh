#!/bin/sh
# One full QA pass over the RUIN addons in a simulated WoW Forever world.
#
#   tests/qa/run_qa.sh <addons-dir> [outdir] [previous-findings.json]
#
# <addons-dir> holds RUIN_Core, RUIN_Finder, ... (folder names as in Interface/AddOns).
# Writes <outdir>/REPORT.md, <outdir>/findings.json and pictures of pages with layout findings.
# Exit code 1 when there are new high/medium findings (see report.py).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
TESTS=$(dirname "$HERE")
ADDONS=$(cd "${1:?usage: run_qa.sh <addons-dir> [outdir] [previous findings.json]}" && pwd)
OUT=${2:-/tmp/ruin-qa}
PREV=${3:-}
LUA=${LUA:-texlua}
export RUIN_CORE_DIR="$ADDONS/RUIN_Core"
[ -f "$RUIN_CORE_DIR/RUIN_Core.toc" ] || { echo "no RUIN_Core in $ADDONS" >&2; exit 2; }

rm -rf "$OUT"; mkdir -p "$OUT"
cd "$TESTS"

echo "1/4 exploring the UI..." >&2
$LUA qa/run51.lua qa/explore.lua "$OUT" > "$OUT/explore.log" 2>&1 || { tail -5 "$OUT/explore.log" >&2; exit 2; }
tail -1 "$OUT/explore.log" >&2

echo "2/4 checking layouts..." >&2
mkdir -p "$OUT/layouts"
cp "$OUT"/scene/*.json "$OUT"/explore--*.json "$OUT/layouts/" 2>/dev/null || true
python3 qa/lint.py "$OUT/layouts" --out "$OUT/layout.jsonl"

echo "3/4 drawing pages with findings..." >&2
mkdir -p "$OUT/pictures"
python3 - "$OUT" <<'PY'
import json, os, shutil, sys
out = sys.argv[1]
pages = []
for l in open(os.path.join(out, "layout.jsonl")):
    f = json.loads(l)
    if f["severity"] in ("high", "medium") and f["page"] not in pages:
        pages.append(f["page"])
pages = pages[:25]
for p in pages:
    shutil.copy(os.path.join(out, "layouts", p + ".json"), os.path.join(out, "pictures", p + ".json"))
open(os.path.join(out, "pictures", "index.txt"), "w").write("\n".join(pages) + "\n")
PY
if [ -s "$OUT/pictures/index.txt" ]; then python3 render/render.py "$OUT/pictures" > "$OUT/pictures/render.log" 2>&1 || { echo "  drawing failed; report has no pictures:" >&2; tail -3 "$OUT/pictures/render.log" >&2; }; fi

echo "4/4 writing the report..." >&2
set +e
python3 qa/report.py "$OUT" --known "$HERE/known-issues.json" ${PREV:+--previous "$PREV"}
rc=$?
echo "report: $OUT/REPORT.md" >&2
exit $rc
