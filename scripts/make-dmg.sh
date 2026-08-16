#!/usr/bin/env bash
set -euo pipefail

APP="${1:?app path}"
OUT="${2:?dmg path}"

if [[ ! -d "$APP" ]]; then
  echo "missing app: $APP" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$(dirname "$OUT")"
cp -R "$APP" "$STAGE/Cracker.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "Cracker" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$OUT"
