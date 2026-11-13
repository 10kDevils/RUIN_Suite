#!/usr/bin/env sh
# Packs the RUIN Gaming Companion App (RUIN Core and every module, at the
# versions this repo pins) into one zip:
#   dist/RUIN_Gaming_Companion_App-<version>.zip
# Extract it into your WoW Forever client's Interface/AddOns folder (or
# World of Warcraft/_retail_/Interface/AddOns for Retail).
set -e
cd "$(dirname "$0")"
git submodule update --init --recursive
VERSION=$(sed -n 's/^## Version: *//p' RUIN_Core/RUIN_Core.toc | tr -d '\r')
OUT="dist/RUIN_Gaming_Companion_App-$VERSION.zip"
mkdir -p dist
rm -f "$OUT"
# the release's signed notice (only when the RUIN_RELEASE_SEED secret is set)
SIGNED=""
if [ -n "$RUIN_RELEASE_SEED" ]; then python3 tools/release/notice.py && SIGNED=1; fi
zip -qr "$OUT" RUIN_Core RUIN_Codex RUIN_Pathfinder RUIN_Finder RUIN_Muster RUIN_Exchange \
    -x '*/.git' '*/.git/*' '*/.gitignore'
# put the unsigned placeholder back, so the RUIN_Core checkout stays clean
if [ -n "$SIGNED" ]; then git -C RUIN_Core checkout -- ReleaseNotice.lua; fi
echo "Built $OUT"
