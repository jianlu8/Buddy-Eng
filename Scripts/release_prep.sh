#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PREP_DIR="${ENGLISHBUDDY_RELEASE_PREP_DIR:-${ROOT_DIR}/Build/ReleasePrep}"
MODEL_ID="gemma-4-e2b"
MODEL_FILENAME="gemma-4-E2B-it.litertlm"
MODEL_VERSION="gemma-4-e2b-v1"
MODEL_URL="https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm?download=true"
MODEL_CACHE_DIR="${ROOT_DIR}/Build/EmbeddedModelCache"
MODEL_CACHE_PATH="${MODEL_CACHE_DIR}/${MODEL_FILENAME}"
STAGED_MODEL_DIR="${PREP_DIR}/EmbeddedModels/${MODEL_ID}"
STAGED_MODEL_PATH="${STAGED_MODEL_DIR}/${MODEL_FILENAME}"
STAGED_MODEL_METADATA_PATH="${STAGED_MODEL_DIR}/EmbeddedModelMetadata.json"
STAGED_SPEECH_DIR="${PREP_DIR}/SpeechAssets"

mkdir -p "${PREP_DIR}" "${MODEL_CACHE_DIR}" "${STAGED_MODEL_DIR}"

write_model_metadata() {
  local destination_path="$1"
  local checksum="$2"
  local expected_size="$3"
  cat > "${destination_path}" <<EOF
{
  "modelID": "${MODEL_ID}",
  "fileName": "${MODEL_FILENAME}",
  "version": "${MODEL_VERSION}",
  "expectedFileSizeBytes": ${expected_size},
  "checksum": "${checksum}"
}
EOF
}

resolve_model_source() {
  if [[ -n "${ENGLISHBUDDY_MODEL_SOURCE:-}" ]]; then
    [[ -f "${ENGLISHBUDDY_MODEL_SOURCE}" ]] || {
      echo "Missing ENGLISHBUDDY_MODEL_SOURCE at ${ENGLISHBUDDY_MODEL_SOURCE}" >&2
      exit 1
    }
    echo "${ENGLISHBUDDY_MODEL_SOURCE}"
    return
  fi

  if [[ -f "${STAGED_MODEL_PATH}" ]]; then
    echo "${STAGED_MODEL_PATH}"
    return
  fi

  if [[ -f "${MODEL_CACHE_PATH}" ]]; then
    echo "${MODEL_CACHE_PATH}"
    return
  fi

  if [[ "${ENGLISHBUDDY_ALLOW_NETWORK_PREP:-0}" != "1" ]]; then
    echo "No staged model found. Set ENGLISHBUDDY_MODEL_SOURCE or allow network prep explicitly." >&2
    exit 1
  fi

  local partial_path="${MODEL_CACHE_PATH}.download"
  echo "Downloading bundled model to ${MODEL_CACHE_PATH}" >&2
  /usr/bin/curl -L --fail --retry 3 --continue-at - --output "${partial_path}" "${MODEL_URL}"
  mv "${partial_path}" "${MODEL_CACHE_PATH}"
  echo "${MODEL_CACHE_PATH}"
}

resolve_speech_source() {
  local candidates=()
  if [[ -n "${ENGLISHBUDDY_SPEECH_ASSET_SOURCE:-}" ]]; then
    candidates+=("${ENGLISHBUDDY_SPEECH_ASSET_SOURCE}")
  fi
  candidates+=(
    "${STAGED_SPEECH_DIR}"
    "${ROOT_DIR}/BundledSpeechAssets"
    "${ROOT_DIR}/Build/SpeechAssetsCache"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -d "${candidate}" ]]; then
      echo "${candidate}"
      return
    fi
  done

  echo "No staged speech assets found. Set ENGLISHBUDDY_SPEECH_ASSET_SOURCE." >&2
  exit 1
}

ENGLISHBUDDY_RUN_HEAVY_PREBUILD=1 "${ROOT_DIR}/Scripts/build_litert_ios_runtime.sh"

MODEL_SOURCE_PATH="$(resolve_model_source)"
/bin/cp -f "${MODEL_SOURCE_PATH}" "${STAGED_MODEL_PATH}"
MODEL_SIZE="$(stat -f%z "${STAGED_MODEL_PATH}")"
MODEL_CHECKSUM="$(shasum -a 256 "${STAGED_MODEL_PATH}" | awk '{print $1}')"
write_model_metadata "${STAGED_MODEL_METADATA_PATH}" "${MODEL_CHECKSUM}" "${MODEL_SIZE}"

SPEECH_SOURCE_DIR="$(resolve_speech_source)"
rm -rf "${STAGED_SPEECH_DIR}"
/usr/bin/ditto "${SPEECH_SOURCE_DIR}" "${STAGED_SPEECH_DIR}"

"${ROOT_DIR}/Scripts/bundle_audit.sh"

echo "Release prep staged artifacts in ${PREP_DIR}" >&2
