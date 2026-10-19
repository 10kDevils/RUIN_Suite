#!/usr/bin/env sh
# Packs every RUIN addon, at the versions this repo pins, into one zip:
#   dist/RUIN_Suite-<version>.zip  ->  extract into World of Warcraft/_retail_/Interface/AddOns
# (or your WoW Forever client's Interface/AddOns folder).
set -e
cd "$(dirname "$0")"
git submodule update --init --recursive
VERSION=$(sed -n 's/^## Version: *//p' RUIN_Core/RUIN_Core.toc | tr -d '\r')
OUT="dist/RUIN_Suite-$VERSION.zip"
mkdir -p dist
rm -f "$OUT"
zip -qr "$OUT" RUIN_Core RUIN_Finder RUIN_Warfront RUIN_Pathfinder RUIN_Codex RUIN_Exchange RUIN_Muster RUIN_Intel \
    -x '*/.git' '*/.git/*' '*/.gitignore'
echo "Built $OUT"
