#!/bin/zsh
set -euo pipefail

export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/local/sbin:${PATH}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_ID="gemma-4-e2b"
MODEL_FILENAME="gemma-4-E2B-it.litertlm"
MODEL_VERSION="gemma-4-e2b-v1"
MODEL_URL="https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm?download=true"
EXPECTED_MODEL_SIZE="2583085056"
CACHE_DIR="${ROOT_DIR}/Build/EmbeddedModelCache"
CACHE_MODEL_PATH="${CACHE_DIR}/${MODEL_FILENAME}"
CACHE_METADATA_PATH="${CACHE_DIR}/EmbeddedModelMetadata.json"

if [[ "${PLATFORM_NAME:-}" != "iphoneos" && "${PLATFORM_NAME:-}" != "iphonesimulator" ]]; then
  echo "Skipping bundled model embed for unsupported platform ${PLATFORM_NAME:-unknown}."
  exit 0
fi

if [[ "${ENGLISHBUDDY_SKIP_MODEL_EMBED:-0}" == "1" ]]; then
  echo "Skipping bundled model embed because ENGLISHBUDDY_SKIP_MODEL_EMBED=1."
  exit 0
fi

if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
  echo "Missing Xcode build environment for bundled model embed." >&2
  exit 1
fi

APP_MODEL_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/EmbeddedModels/${MODEL_ID}"
APP_MODEL_PATH="${APP_MODEL_DIR}/${MODEL_FILENAME}"
APP_METADATA_PATH="${APP_MODEL_DIR}/EmbeddedModelMetadata.json"
LEGACY_APP_MODEL_PATH="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/EmbeddedModels/${MODEL_FILENAME}"
LEGACY_APP_METADATA_PATH="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/EmbeddedModels/EmbeddedModelMetadata.json"

mkdir -p "${CACHE_DIR}" "${APP_MODEL_DIR}"

rm -f "${LEGACY_APP_MODEL_PATH}" "${LEGACY_APP_METADATA_PATH}"

file_size() {
  stat -f%z "$1"
}

read_metadata_value() {
  local metadata_path="$1"
  local key="$2"
  /usr/bin/plutil -extract "${key}" raw -o - "${metadata_path}" 2>/dev/null || true
}

write_metadata() {
  local metadata_path="$1"
  local checksum="$2"
  cat > "${metadata_path}" <<EOF
{
  "modelID": "${MODEL_ID}",
  "fileName": "${MODEL_FILENAME}",
  "version": "${MODEL_VERSION}",
  "expectedFileSizeBytes": ${EXPECTED_MODEL_SIZE},
  "checksum": "${checksum}"
}
EOF
}

clone_or_copy() {
  local source_path="$1"
  local destination_path="$2"

  rm -f "${destination_path}"
  if /bin/cp -c -f "${source_path}" "${destination_path}" 2>/dev/null; then
    return
  fi
  /bin/cp -f "${source_path}" "${destination_path}"
}

ensure_expected_size() {
  local candidate_path="$1"
  if [[ ! -f "${candidate_path}" ]]; then
    return 1
  fi
  [[ "$(file_size "${candidate_path}")" == "${EXPECTED_MODEL_SIZE}" ]]
}

resolve_source_model_path() {
  if [[ -n "${ENGLISHBUDDY_MODEL_SOURCE:-}" ]]; then
    if [[ ! -f "${ENGLISHBUDDY_MODEL_SOURCE}" ]]; then
      echo "ENGLISHBUDDY_MODEL_SOURCE points to a missing file: ${ENGLISHBUDDY_MODEL_SOURCE}" >&2
      exit 1
    fi
    if ! ensure_expected_size "${ENGLISHBUDDY_MODEL_SOURCE}"; then
      echo "Local model source has an unexpected size: ${ENGLISHBUDDY_MODEL_SOURCE}" >&2
      exit 1
    fi
    echo "${ENGLISHBUDDY_MODEL_SOURCE}"
    return
  fi

  if ensure_expected_size "${CACHE_MODEL_PATH}"; then
    echo "${CACHE_MODEL_PATH}"
    return
  fi

  local partial_path="${CACHE_MODEL_PATH}.download"
  echo "Fetching bundled model to ${CACHE_MODEL_PATH}" >&2
  /usr/bin/curl -L --fail --retry 3 --continue-at - --output "${partial_path}" "${MODEL_URL}"

  if ! ensure_expected_size "${partial_path}"; then
    echo "Downloaded bundled model size mismatch." >&2
    rm -f "${partial_path}"
    exit 1
  fi

  mv "${partial_path}" "${CACHE_MODEL_PATH}"
  echo "${CACHE_MODEL_PATH}"
}

source_model_path="$(resolve_source_model_path)"

if ! ensure_expected_size "${source_model_path}"; then
  echo "Bundled model source failed size verification: ${source_model_path}" >&2
  exit 1
fi

cached_checksum="$(read_metadata_value "${CACHE_METADATA_PATH}" checksum)"
cached_size="$(read_metadata_value "${CACHE_METADATA_PATH}" expectedFileSizeBytes)"
if [[ "${source_model_path}" != "${CACHE_MODEL_PATH}" || "${cached_size}" != "${EXPECTED_MODEL_SIZE}" || -z "${cached_checksum}" ]]; then
  echo "Calculating SHA256 for bundled model..." >&2
  cached_checksum="$(/usr/bin/shasum -a 256 "${source_model_path}" | awk '{print $1}')"
  write_metadata "${CACHE_METADATA_PATH}" "${cached_checksum}"
fi

app_checksum="$(read_metadata_value "${APP_METADATA_PATH}" checksum)"
app_size="$(read_metadata_value "${APP_METADATA_PATH}" expectedFileSizeBytes)"
if [[ ! -f "${APP_MODEL_PATH}" || "$(file_size "${APP_MODEL_PATH}")" != "${EXPECTED_MODEL_SIZE}" || "${app_checksum}" != "${cached_checksum}" || "${app_size}" != "${EXPECTED_MODEL_SIZE}" ]]; then
  echo "Embedding bundled model into ${APP_MODEL_PATH}" >&2
  clone_or_copy "${source_model_path}" "${APP_MODEL_PATH}"
fi

write_metadata "${APP_METADATA_PATH}" "${cached_checksum}"
echo "Bundled model is ready inside the app package." >&2
