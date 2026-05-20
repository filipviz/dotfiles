#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OCR="$SCRIPT_DIR/ocr"

if [ ! -x "$OCR" ]; then
    osascript -e 'display notification "ocr binary not found — run: swiftc -O -o ocr ocr.swift" with title "OCR Screenshot"'
    exit 1
fi

tmp=$(mktemp /tmp/ocr_XXXXX.png)
trap 'rm -f "$tmp"' EXIT

screencapture -i "$tmp"

# screencapture exits 0 even when cancelled, but the file will be empty
if [ ! -s "$tmp" ]; then
    exit 0
fi

text=$("$OCR" "$tmp")

if [ -z "$text" ]; then
    osascript -e 'display notification "No text detected" with title "OCR Screenshot"'
    exit 0
fi

printf '%s' "$text" | pbcopy
osascript -e 'display notification "Text copied to clipboard" with title "OCR Screenshot"'
