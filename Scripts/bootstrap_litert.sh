#!/bin/zsh
set -euo pipefail

# Xcode build phases do not always inherit interactive shell PATH entries.
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:${PATH}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LITERT_DIR="${ROOT_DIR}/third_party/LiteRT-LM"

if [[ ! -d "${LITERT_DIR}" ]]; then
  echo "LiteRT-LM source is missing at ${LITERT_DIR}." >&2
  exit 1
fi

if ! command -v git-lfs >/dev/null 2>&1; then
  echo "git-lfs is required. Install it with: brew install git-lfs" >&2
  echo "Current PATH: ${PATH}" >&2
  exit 1
fi

if ! command -v bazelisk >/dev/null 2>&1; then
  echo "bazelisk is required. Install it with: brew install bazelisk" >&2
  echo "Current PATH: ${PATH}" >&2
  exit 1
fi

git lfs install >/dev/null
git -C "${LITERT_DIR}" lfs pull

echo "LiteRT-LM bootstrap complete."
