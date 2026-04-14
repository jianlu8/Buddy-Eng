#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LITERT_DIR="${ROOT_DIR}/third_party/LiteRT-LM"
OUTPUT_DIR="${ROOT_DIR}/Build/LiteRTLM"
HEADER_DIR="${OUTPUT_DIR}/Headers"
PATCHED_PROVIDER_DIR="${OUTPUT_DIR}/PatchedProviders"
PATCHED_RUNTIME_DIR="${OUTPUT_DIR}/PatchedRuntimes"
STAMP_FILE="${OUTPUT_DIR}/build.stamp"
RUNTIME_TARGET="//englishbuddy:litert_lm_c_api_shared"
EMPTY_HEADERS="${HEADER_DIR}/Empty"

mkdir -p "${OUTPUT_DIR}" "${EMPTY_HEADERS}" "${PATCHED_PROVIDER_DIR}" "${PATCHED_RUNTIME_DIR}"

if [[ ! -d "${LITERT_DIR}" ]]; then
  echo "Missing vendored LiteRT-LM at ${LITERT_DIR}" >&2
  exit 1
fi

"${ROOT_DIR}/Scripts/bootstrap_litert.sh" >/dev/null

STAMP_INPUTS=(
  "${LITERT_DIR}/WORKSPACE"
  "${LITERT_DIR}/.bazelrc"
  "${LITERT_DIR}/englishbuddy/BUILD"
  "${LITERT_DIR}/c/BUILD"
  "${LITERT_DIR}/prebuilt/ios_arm64/libGemmaModelConstraintProvider.dylib"
  "${LITERT_DIR}/prebuilt/ios_sim_arm64/libGemmaModelConstraintProvider.dylib"
  "${ROOT_DIR}/Scripts/build_litert_ios_runtime.sh"
)

needs_rebuild=0
if [[ ! -f "${OUTPUT_DIR}/LiteRTLMRuntime.xcframework/Info.plist" ]]; then
  needs_rebuild=1
elif [[ ! -f "${OUTPUT_DIR}/GemmaModelConstraintProvider.xcframework/Info.plist" ]]; then
  needs_rebuild=1
elif [[ ! -f "${STAMP_FILE}" ]]; then
  needs_rebuild=1
else
  for input in "${STAMP_INPUTS[@]}"; do
    if [[ "${input}" -nt "${STAMP_FILE}" ]]; then
      needs_rebuild=1
      break
    fi
  done
fi

if [[ "${needs_rebuild}" -eq 0 ]]; then
  exit 0
fi

build_variant() {
  local config="$1"
  (cd "${LITERT_DIR}" && bazelisk build --config="${config}" "${RUNTIME_TARGET}" >/dev/null)
}

find_bazel_binary() {
  local config="$1"
  (cd "${LITERT_DIR}" && bazelisk cquery --config="${config}" --output=files "${RUNTIME_TARGET}") \
    | tr ' ' '\n' \
    | rg 'litert_lm_c_api_shared(\.dylib|)$' \
    | head -n 1
}

build_variant ios_arm64
build_variant ios_sim_arm64

DEVICE_RUNTIME_RELATIVE="$(find_bazel_binary ios_arm64)"
SIM_RUNTIME_RELATIVE="$(find_bazel_binary ios_sim_arm64)"

if [[ -z "${DEVICE_RUNTIME_RELATIVE}" || -z "${SIM_RUNTIME_RELATIVE}" ]]; then
  echo "Unable to locate Bazel output for ${RUNTIME_TARGET}." >&2
  exit 1
fi

DEVICE_RUNTIME="${LITERT_DIR}/${DEVICE_RUNTIME_RELATIVE}"
SIM_RUNTIME="${LITERT_DIR}/${SIM_RUNTIME_RELATIVE}"
DEVICE_RUNTIME_PATCHED_DIR="${PATCHED_RUNTIME_DIR}/ios-arm64"
SIM_RUNTIME_PATCHED_DIR="${PATCHED_RUNTIME_DIR}/ios-arm64-simulator"
DEVICE_RUNTIME_PATCHED="${DEVICE_RUNTIME_PATCHED_DIR}/liblitert_lm_c_api_shared.dylib"
SIM_RUNTIME_PATCHED="${SIM_RUNTIME_PATCHED_DIR}/liblitert_lm_c_api_shared.dylib"
DEVICE_PROVIDER_SOURCE="${LITERT_DIR}/prebuilt/ios_arm64/libGemmaModelConstraintProvider.dylib"
SIM_PROVIDER_SOURCE="${LITERT_DIR}/prebuilt/ios_sim_arm64/libGemmaModelConstraintProvider.dylib"
DEVICE_PROVIDER_PATCHED_DIR="${PATCHED_PROVIDER_DIR}/ios-arm64"
SIM_PROVIDER_PATCHED_DIR="${PATCHED_PROVIDER_DIR}/ios-arm64-simulator"
DEVICE_PROVIDER_PATCHED="${DEVICE_PROVIDER_PATCHED_DIR}/libGemmaModelConstraintProvider.dylib"
SIM_PROVIDER_PATCHED="${SIM_PROVIDER_PATCHED_DIR}/libGemmaModelConstraintProvider.dylib"

if [[ ! -f "${DEVICE_RUNTIME}" || ! -f "${SIM_RUNTIME}" ]]; then
  echo "LiteRT runtime dylib is missing after Bazel build." >&2
  exit 1
fi

if [[ ! -f "${DEVICE_PROVIDER_SOURCE}" || ! -f "${SIM_PROVIDER_SOURCE}" ]]; then
  echo "Gemma model constraint provider dylib is missing from the vendored LiteRT-LM checkout." >&2
  exit 1
fi

patch_provider_build_version() {
  local platform="$1"
  local input="$2"
  local output="$3"
  local sdk_version="$4"

  mkdir -p "$(dirname "${output}")"
  xcrun vtool \
    -set-build-version "${platform}" 17.0 "${sdk_version}" \
    -replace \
    -output "${output}" \
    "${input}" >/dev/null
}

IOS_SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
IOS_SIM_SDK_VERSION="$(xcrun --sdk iphonesimulator --show-sdk-version)"

patch_provider_build_version ios "${DEVICE_PROVIDER_SOURCE}" "${DEVICE_PROVIDER_PATCHED}" "${IOS_SDK_VERSION}"
patch_provider_build_version iossim "${SIM_PROVIDER_SOURCE}" "${SIM_PROVIDER_PATCHED}" "${IOS_SIM_SDK_VERSION}"

patch_runtime_install_name() {
  local input="$1"
  local output="$2"

  mkdir -p "$(dirname "${output}")"
  cp "${input}" "${output}"
  chmod u+w "${output}"
  install_name_tool -id "@rpath/liblitert_lm_c_api_shared.dylib" "${output}"
}

patch_runtime_install_name "${DEVICE_RUNTIME}" "${DEVICE_RUNTIME_PATCHED}"
patch_runtime_install_name "${SIM_RUNTIME}" "${SIM_RUNTIME_PATCHED}"

rm -rf "${OUTPUT_DIR}/LiteRTLMRuntime.xcframework" "${OUTPUT_DIR}/GemmaModelConstraintProvider.xcframework"

xcodebuild -create-xcframework \
  -library "${DEVICE_RUNTIME_PATCHED}" -headers "${EMPTY_HEADERS}" \
  -library "${SIM_RUNTIME_PATCHED}" -headers "${EMPTY_HEADERS}" \
  -output "${OUTPUT_DIR}/LiteRTLMRuntime.xcframework" >/dev/null

xcodebuild -create-xcframework \
  -library "${DEVICE_PROVIDER_PATCHED}" -headers "${EMPTY_HEADERS}" \
  -library "${SIM_PROVIDER_PATCHED}" -headers "${EMPTY_HEADERS}" \
  -output "${OUTPUT_DIR}/GemmaModelConstraintProvider.xcframework" >/dev/null

touch "${STAMP_FILE}"
