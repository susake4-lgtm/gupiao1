#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EXTERNAL_DIR="$ROOT_DIR/external/daily_stock_analysis"
VENV_DIR="$EXTERNAL_DIR/.venv"
PYTHON_BIN="${PYTHON_BIN:-python3}"
UPSTREAM_URL="${DSA_REPO_URL:-https://github.com/ZhuLinsen/daily_stock_analysis.git}"

if [ ! -d "$ROOT_DIR/external" ]; then
  mkdir -p "$ROOT_DIR/external"
fi

if [ ! -d "$EXTERNAL_DIR/.git" ]; then
  echo "[bootstrap] cloning daily_stock_analysis into $EXTERNAL_DIR"
  git clone --depth 1 "$UPSTREAM_URL" "$EXTERNAL_DIR"
else
  echo "[bootstrap] updating existing checkout in $EXTERNAL_DIR"
  git -C "$EXTERNAL_DIR" pull --ff-only
fi

if [ ! -d "$VENV_DIR" ]; then
  echo "[bootstrap] creating virtual environment"
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

source "$VENV_DIR/bin/activate"

echo "[bootstrap] upgrading pip"
python -m pip install --upgrade pip

echo "[bootstrap] installing Python dependencies"
pip install -r "$EXTERNAL_DIR/requirements.txt"

echo "[bootstrap] done"
echo "[bootstrap] upstream revision: $(git -C "$EXTERNAL_DIR" rev-parse HEAD)"
