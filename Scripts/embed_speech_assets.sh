#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ "${PLATFORM_NAME:-}" != "iphoneos" && "${PLATFORM_NAME:-}" != "iphonesimulator" ]]; then
  echo "Skipping speech asset embed for unsupported platform ${PLATFORM_NAME:-unknown}."
  exit 0
fi

if [[ "${ENGLISHBUDDY_SKIP_SPEECH_ASSET_EMBED:-0}" == "1" ]]; then
  echo "Skipping speech asset embed because ENGLISHBUDDY_SKIP_SPEECH_ASSET_EMBED=1."
  exit 0
fi

if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
  echo "Missing Xcode build environment for speech asset embed." >&2
  exit 1
fi

APP_SPEECH_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/SpeechAssets"
MANIFEST_NAME="Manifest.json"
BUILD_FACTS_NAME="RuntimeBuild.json"
STRICT_RELEASE_LANE=0

if [[ "${ENGLISHBUDDY_RELEASE_LANE:-0}" == "1" || "${ENGLISHBUDDY_REQUIRE_BUNDLED_SPEECH:-0}" == "1" ]]; then
  STRICT_RELEASE_LANE=1
fi

if [[ "${CONFIGURATION:-}" == "Release" && "${ENGLISHBUDDY_ALLOW_SPEECH_FALLBACK_IN_RELEASE:-0}" != "1" ]]; then
  STRICT_RELEASE_LANE=1
fi

fail_or_warn() {
  local message="$1"
  if [[ "${STRICT_RELEASE_LANE}" == "1" ]]; then
    echo "${message}" >&2
    exit 1
  fi
  echo "${message}" >&2
}

resolve_source_dir() {
  if [[ -n "${ENGLISHBUDDY_SPEECH_ASSET_SOURCE:-}" ]]; then
    if [[ ! -d "${ENGLISHBUDDY_SPEECH_ASSET_SOURCE}" ]]; then
      echo "ENGLISHBUDDY_SPEECH_ASSET_SOURCE points to a missing directory: ${ENGLISHBUDDY_SPEECH_ASSET_SOURCE}" >&2
      exit 1
    fi
    echo "${ENGLISHBUDDY_SPEECH_ASSET_SOURCE}"
    return
  fi

  local candidates=(
    "${ROOT_DIR}/Build/ReleasePrep/SpeechAssets"
    "${ROOT_DIR}/BundledSpeechAssets"
    "${ROOT_DIR}/Build/SpeechAssetsCache"
  )

  for candidate in "${candidates[@]}"; do
    if [[ -d "${candidate}" ]]; then
      echo "${candidate}"
      return
    fi
  done
}

path_size_bytes() {
  local path="$1"
  if [[ -d "${path}" ]]; then
    find "${path}" -type f -print0 | xargs -0 stat -f "%z" 2>/dev/null | awk '{sum += $1} END {print sum + 0}'
  else
    stat -f "%z" "${path}" 2>/dev/null || echo 0
  fi
}

path_checksum() {
  local path="$1"
  if [[ -d "${path}" ]]; then
    python3 - "$path" <<'PY'
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
h = hashlib.sha256()
for child in sorted(p for p in root.rglob("*") if p.is_file()):
    rel = child.relative_to(root).as_posix().encode("utf-8")
    h.update(rel)
    h.update(b"\0")
    h.update(hashlib.sha256(child.read_bytes()).hexdigest().encode("utf-8"))
    h.update(b"\0")
print(h.hexdigest())
PY
  else
    shasum -a 256 "${path}" | awk '{print $1}'
  fi
}

parse_boolean_flag() {
  local raw_value="${1:-}"
  if [[ -z "${raw_value}" ]]; then
    echo ""
    return
  fi

  case "${raw_value:l}" in
    1|true|yes|y|on)
      echo "1"
      ;;
    0|false|no|n|off)
      echo "0"
      ;;
    *)
      echo ""
      ;;
  esac
}

resolve_boolean_flag() {
  local inferred_default="$1"
  shift

  local candidate=""
  for value in "$@"; do
    candidate="$(parse_boolean_flag "${value}")"
    if [[ -n "${candidate}" ]]; then
      echo "${candidate}"
      return
    fi
  done

  echo "${inferred_default}"
}

manifest_contains_runtime() {
  local manifest_path="$1"
  local runtime_id="$2"

  if [[ ! -f "${manifest_path}" ]]; then
    echo "0"
    return
  fi

  python3 - "${manifest_path}" "${runtime_id}" <<'PY'
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
runtime_id = sys.argv[2]

with manifest_path.open("r", encoding="utf-8") as handle:
    manifest = json.load(handle)

found = any(str(asset.get("runtimeID") or "").strip() == runtime_id for asset in manifest.get("assets", []))
print("1" if found else "0")
PY
}

write_runtime_build_facts() {
  local output_path="$1"
  local sherpa_enabled="$2"
  local kokoro_enabled="$3"
  local piper_enabled="$4"
  local sherpa_bridge_linked="$5"
  local kokoro_bridge_linked="$6"
  local piper_bridge_linked="$7"
  local strict_release_lane="$8"
  local allows_runtime_fallback="$9"

  python3 - "${output_path}" "${sherpa_enabled}" "${kokoro_enabled}" "${piper_enabled}" "${sherpa_bridge_linked}" "${kokoro_bridge_linked}" "${piper_bridge_linked}" "${strict_release_lane}" "${allows_runtime_fallback}" <<'PY'
import json
import pathlib
import sys

output_path = pathlib.Path(sys.argv[1])

def as_bool(raw: str) -> bool:
    return raw == "1"

payload = {
    "sherpaOnnxEnabled": as_bool(sys.argv[2]),
    "kokoroEnabled": as_bool(sys.argv[3]),
    "piperEnabled": as_bool(sys.argv[4]),
    "sherpaOnnxBridgeLinked": as_bool(sys.argv[5]),
    "kokoroBridgeLinked": as_bool(sys.argv[6]),
    "piperBridgeLinked": as_bool(sys.argv[7]),
    "strictReleaseLane": as_bool(sys.argv[8]),
    "allowsRuntimeFallback": as_bool(sys.argv[9]),
}

output_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

validate_manifest() {
  local speech_dir="$1"
  local manifest_path="${speech_dir}/${MANIFEST_NAME}"

  if [[ ! -f "${manifest_path}" ]]; then
    fail_or_warn "Speech asset manifest is missing at ${manifest_path}."
    return
  fi

  if ! python3 - "${manifest_path}" "${speech_dir}" <<'PY'
import hashlib
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
speech_dir = pathlib.Path(sys.argv[2])

with manifest_path.open("r", encoding="utf-8") as handle:
    manifest = json.load(handle)

def path_size_bytes(path: pathlib.Path) -> int:
    if path.is_dir():
        return sum(child.stat().st_size for child in path.rglob("*") if child.is_file())
    return path.stat().st_size

def path_checksum(path: pathlib.Path) -> str:
    if path.is_dir():
        h = hashlib.sha256()
        for child in sorted(p for p in path.rglob("*") if p.is_file()):
            rel = child.relative_to(path).as_posix().encode("utf-8")
            h.update(rel)
            h.update(b"\0")
            h.update(hashlib.sha256(child.read_bytes()).hexdigest().encode("utf-8"))
            h.update(b"\0")
        return h.hexdigest()
    return hashlib.sha256(path.read_bytes()).hexdigest()

errors: list[str] = []
assets = manifest.get("assets", [])
for asset in assets:
    asset_id = str(asset.get("assetID") or "").strip()
    runtime_type = str(asset.get("runtimeType") or "").strip()
    runtime_id = str(asset.get("runtimeID") or "").strip()
    relative_path = str(asset.get("relativePath") or asset_id).strip() or asset_id
    expected_size = asset.get("size")
    checksum = str(asset.get("checksum") or "").strip()
    voice_bundle_id = str(asset.get("voiceBundleID") or "").strip()
    supported_voice_bundle_ids = [
        str(item).strip()
        for item in (asset.get("supportedVoiceBundleIDs") or [])
        if str(item).strip()
    ]

    if not asset_id:
        errors.append("Speech asset manifest contains an entry without assetID.")
        continue

    asset_path = speech_dir / relative_path
    if not asset_path.exists():
        errors.append(f"Speech asset {asset_id} is declared in Manifest.json but missing at {asset_path}.")
        continue

    if runtime_type not in {"asr", "tts"}:
        errors.append(f"Speech asset {asset_id} has unsupported runtimeType '{runtime_type}'.")

    if not runtime_id:
        errors.append(f"Speech asset {asset_id} is missing runtimeID.")

    if runtime_type == "tts" and not voice_bundle_id and not supported_voice_bundle_ids:
        errors.append(f"Speech asset {asset_id} is a TTS asset but voice bundle bindings are missing.")

    if expected_size not in (None, ""):
        actual_size = path_size_bytes(asset_path)
        if int(expected_size) != actual_size:
            errors.append(f"Speech asset {asset_id} has size {actual_size}, expected {expected_size}.")

    if checksum:
        actual_checksum = path_checksum(asset_path)
        if actual_checksum != checksum:
            errors.append(f"Speech asset {asset_id} checksum mismatch: {actual_checksum} != {checksum}.")

if errors:
    for error in errors:
        print(error)
    sys.exit(1)
PY
  then
    fail_or_warn "Bundled speech asset validation failed."
  fi
}

SOURCE_DIR="$(resolve_source_dir || true)"
rm -rf "${APP_SPEECH_DIR}"

if [[ -z "${SOURCE_DIR}" ]]; then
  fail_or_warn "No bundled speech assets found. The build cannot package bundled speech assets."
  exit 0
fi

mkdir -p "${APP_SPEECH_DIR}"
/usr/bin/ditto "${SOURCE_DIR}" "${APP_SPEECH_DIR}"

if [[ ! -f "${APP_SPEECH_DIR}/${MANIFEST_NAME}" ]]; then
  fail_or_warn "Bundled speech assets were copied, but ${MANIFEST_NAME} is missing."
  if [[ "${STRICT_RELEASE_LANE}" != "1" ]]; then
    echo "Bundled speech assets copied to ${APP_SPEECH_DIR} without manifest; runtime will stay in fallback mode." >&2
    exit 0
  fi
fi

validate_manifest "${APP_SPEECH_DIR}"

SHERPA_ASSET_PRESENT="$(manifest_contains_runtime "${APP_SPEECH_DIR}/${MANIFEST_NAME}" "sherpa-onnx-asr")"
KOKORO_ASSET_PRESENT="$(manifest_contains_runtime "${APP_SPEECH_DIR}/${MANIFEST_NAME}" "kokoro-tts")"
PIPER_ASSET_PRESENT="$(manifest_contains_runtime "${APP_SPEECH_DIR}/${MANIFEST_NAME}" "piper-tts")"

SHERPA_ENABLED="$(resolve_boolean_flag "${SHERPA_ASSET_PRESENT}" "${ENGLISHBUDDY_ENABLE_SHERPA_ONNX:-}" "${ENGLISHBUDDY_SPEECH_ENABLE_SHERPA_ONNX:-}")"
KOKORO_ENABLED="$(resolve_boolean_flag "${KOKORO_ASSET_PRESENT}" "${ENGLISHBUDDY_ENABLE_KOKORO:-}" "${ENGLISHBUDDY_SPEECH_ENABLE_KOKORO:-}" "${ENGLISHBUDDY_ENABLE_PIPER:-}" "${ENGLISHBUDDY_SPEECH_ENABLE_PIPER:-}")"
SHERPA_BRIDGE_LINKED="$(resolve_boolean_flag "0" "${ENGLISHBUDDY_LINK_SHERPA_ONNX:-}" "${ENGLISHBUDDY_SPEECH_BRIDGE_SHERPA_ONNX:-}")"
KOKORO_BRIDGE_LINKED="$(resolve_boolean_flag "0" "${ENGLISHBUDDY_LINK_KOKORO:-}" "${ENGLISHBUDDY_SPEECH_BRIDGE_KOKORO:-}" "${ENGLISHBUDDY_LINK_PIPER:-}" "${ENGLISHBUDDY_SPEECH_BRIDGE_PIPER:-}")"
ALLOWS_RUNTIME_FALLBACK="$([[ "${STRICT_RELEASE_LANE}" == "1" ]] && echo "0" || echo "1")"

if [[ "${PIPER_ASSET_PRESENT}" == "1" ]]; then
  PIPER_ENABLED="$(resolve_boolean_flag "${PIPER_ASSET_PRESENT}" "${ENGLISHBUDDY_ENABLE_PIPER:-}" "${ENGLISHBUDDY_SPEECH_ENABLE_PIPER:-}")"
  PIPER_BRIDGE_LINKED="$(resolve_boolean_flag "0" "${ENGLISHBUDDY_LINK_PIPER:-}" "${ENGLISHBUDDY_SPEECH_BRIDGE_PIPER:-}")"
else
  PIPER_ENABLED="0"
  PIPER_BRIDGE_LINKED="0"
fi

if [[ "${SHERPA_ENABLED}" == "1" && "${SHERPA_BRIDGE_LINKED}" != "1" ]]; then
  fail_or_warn "Bundled sherpa-onnx assets are packaged, but the sherpa-onnx bridge is not linked for this build."
fi

if [[ "${KOKORO_ENABLED}" == "1" && "${KOKORO_BRIDGE_LINKED}" != "1" ]]; then
  fail_or_warn "Bundled Kokoro assets are packaged, but the Kokoro bridge is not linked for this build."
fi

if [[ "${PIPER_ENABLED}" == "1" && "${PIPER_BRIDGE_LINKED}" != "1" ]]; then
  fail_or_warn "Bundled Piper assets are packaged, but the Piper bridge is not linked for this build."
fi

write_runtime_build_facts \
  "${APP_SPEECH_DIR}/${BUILD_FACTS_NAME}" \
  "${SHERPA_ENABLED}" \
  "${KOKORO_ENABLED}" \
  "${PIPER_ENABLED}" \
  "${SHERPA_BRIDGE_LINKED}" \
  "${KOKORO_BRIDGE_LINKED}" \
  "${PIPER_BRIDGE_LINKED}" \
  "${STRICT_RELEASE_LANE}" \
  "${ALLOWS_RUNTIME_FALLBACK}"

echo "Bundled speech assets copied to ${APP_SPEECH_DIR}" >&2
