#!/usr/bin/env bash
set -euo pipefail

PNR_DIR=${PNR_DIR:-librelane}

echo "[LibreLane] Running PNR..."
librelane $PNR_DIR/config.json

echo "[LibreLane] Printing results..."
(cd "$PNR_DIR" && python3 summary.py --summary --timing --copy)