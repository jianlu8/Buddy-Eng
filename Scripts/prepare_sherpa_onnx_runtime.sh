#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSPECT_DIR="${ROOT_DIR}/Build/SherpaInspect"
EXTRACT_DIR="${INSPECT_DIR}/sherpa-ios/build-ios"
RUNTIME_DIR="${ROOT_DIR}/Build/SherpaOnnx"
STAMP_PATH="${RUNTIME_DIR}/build.stamp"

if [[ -f "${STAMP_PATH}" && -d "${RUNTIME_DIR}/sherpa-onnx.xcframework" && -d "${RUNTIME_DIR}/onnxruntime.xcframework" ]]; then
  exit 0
fi

mkdir -p "${INSPECT_DIR}" "${RUNTIME_DIR}"

if [[ ! -d "${EXTRACT_DIR}" ]]; then
  ARCHIVE_PATH="${INSPECT_DIR}/sherpa-onnx-ios.tar.bz2"
  if [[ ! -f "${ARCHIVE_PATH}" ]]; then
    echo "Missing sherpa iOS runtime archive at ${ARCHIVE_PATH}." >&2
    exit 1
  fi

  rm -rf "${INSPECT_DIR}/sherpa-ios"
  mkdir -p "${INSPECT_DIR}/sherpa-ios"
  tar -xjf "${ARCHIVE_PATH}" -C "${INSPECT_DIR}/sherpa-ios"
fi

SOURCE_SHERPA="${EXTRACT_DIR}/sherpa-onnx.xcframework"
SOURCE_ONNX="${EXTRACT_DIR}/ios-onnxruntime/onnxruntime.xcframework"

if [[ ! -d "${SOURCE_ONNX}" && -d "${EXTRACT_DIR}/ios-onnxruntime/1.17.1/onnxruntime.xcframework" ]]; then
  SOURCE_ONNX="${EXTRACT_DIR}/ios-onnxruntime/1.17.1/onnxruntime.xcframework"
fi

if [[ ! -d "${SOURCE_SHERPA}" || ! -d "${SOURCE_ONNX}" ]]; then
  echo "Extracted sherpa runtime is incomplete. Expected sherpa-onnx.xcframework and onnxruntime.xcframework." >&2
  exit 1
fi

rm -rf "${RUNTIME_DIR}/sherpa-onnx.xcframework" "${RUNTIME_DIR}/onnxruntime.xcframework"
/usr/bin/ditto "${SOURCE_SHERPA}" "${RUNTIME_DIR}/sherpa-onnx.xcframework"
/usr/bin/ditto "${SOURCE_ONNX}" "${RUNTIME_DIR}/onnxruntime.xcframework"
touch "${STAMP_PATH}"

echo "Prepared sherpa-onnx runtime in ${RUNTIME_DIR}" >&2
