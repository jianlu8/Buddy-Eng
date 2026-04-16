#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PREP_DIR="${ENGLISHBUDDY_RELEASE_PREP_DIR:-${ROOT_DIR}/Build/ReleasePrep}"
MODEL_ID="gemma-4-e2b"
MODEL_FILENAME="gemma-4-E2B-it.litertlm"
REPORT_DIR="${PREP_DIR}/ReleaseAudit"
REPORT_PATH="${REPORT_DIR}/BundleAuditReport.json"
LEGACY_REPORT_PATH="${PREP_DIR}/BundleAuditReport.json"

mkdir -p "${PREP_DIR}" "${REPORT_DIR}"

python3 - "${PREP_DIR}" "${MODEL_ID}" "${MODEL_FILENAME}" "${REPORT_PATH}" "${LEGACY_REPORT_PATH}" <<'PY'
import hashlib
import json
import pathlib
import sys

prep_dir = pathlib.Path(sys.argv[1])
model_id = sys.argv[2]
model_filename = sys.argv[3]
report_path = pathlib.Path(sys.argv[4])
legacy_report_path = pathlib.Path(sys.argv[5])

issues = []
embedded_model_ids = []
speech_asset_ids = []

model_path = prep_dir / "EmbeddedModels" / model_id / model_filename
metadata_path = prep_dir / "EmbeddedModels" / model_id / "EmbeddedModelMetadata.json"
if model_path.exists():
    embedded_model_ids.append(model_id)
else:
    issues.append({"severity": "error", "message": f"Missing bundled model at {model_path}"})

if metadata_path.exists() is False:
    issues.append({"severity": "error", "message": f"Missing bundled model metadata at {metadata_path}"})
elif model_path.exists():
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    expected_file_name = str(metadata.get("fileName") or "").strip()
    expected_size = metadata.get("expectedFileSizeBytes")
    expected_checksum = str(metadata.get("checksum") or "").strip()

    if expected_file_name and expected_file_name != model_filename:
        issues.append({"severity": "error", "message": f"Bundled model metadata points to {expected_file_name}, expected {model_filename}."})

    actual_size = model_path.stat().st_size
    if expected_size not in (None, "") and actual_size != int(expected_size):
        issues.append({"severity": "error", "message": f"Bundled model size is {actual_size} bytes, expected {expected_size} bytes."})

    if expected_checksum:
        actual_checksum = hashlib.sha256(model_path.read_bytes()).hexdigest()
        if actual_checksum != expected_checksum:
            issues.append({"severity": "error", "message": f"Bundled model checksum mismatch for {model_filename}."})

speech_dir = prep_dir / "SpeechAssets"
manifest_path = speech_dir / "Manifest.json"
runtime_build_path = speech_dir / "RuntimeBuild.json"
manifest = None

if not speech_dir.exists():
    issues.append({"severity": "error", "message": f"Missing speech asset directory at {speech_dir}"})
elif not manifest_path.exists():
    issues.append({"severity": "error", "message": f"Missing speech asset manifest at {manifest_path}"})
else:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    speech_asset_ids = [str(asset.get("assetID") or "").strip() for asset in manifest.get("assets", []) if str(asset.get("assetID") or "").strip()]
    required_assets = {
        "sherpa-onnx-en-us-streaming": {
            "runtimeID": "sherpa-onnx-asr",
            "runtimeType": "asr",
            "locale": "en-US",
            "voiceBundleID": None,
        },
        "kokoro-multi-lang-v1_0": {
            "runtimeID": "kokoro-tts",
            "runtimeType": "tts",
            "locale": None,
            "supportedVoiceBundleIDs": ["nova-voice", "lyra-voice", "michael-voice", "george-voice"],
        },
    }
    missing_ids = sorted(set(required_assets).difference(speech_asset_ids))
    for asset_id in missing_ids:
        issues.append({"severity": "error", "message": f"Required speech asset is missing from manifest: {asset_id}"})

    asset_by_id = {}
    for asset in manifest.get("assets", []):
        asset_id = str(asset.get("assetID") or "").strip()
        if asset_id:
            asset_by_id[asset_id] = asset

    for asset_id, expected in required_assets.items():
        asset = asset_by_id.get(asset_id)
        if asset is None:
            continue

        runtime_id = str(asset.get("runtimeID") or "").strip()
        runtime_type = str(asset.get("runtimeType") or "").strip()
        locale = str(asset.get("locale") or "").strip()
        voice_bundle_id = str(asset.get("voiceBundleID") or "").strip()
        supported_voice_bundle_ids = [
            str(item).strip()
            for item in (asset.get("supportedVoiceBundleIDs") or [])
            if str(item).strip()
        ]
        relative_path = str(asset.get("relativePath") or asset_id).strip() or asset_id
        asset_path = speech_dir / relative_path

        if runtime_id != expected["runtimeID"]:
            issues.append({"severity": "error", "message": f"Speech asset {asset_id} declares runtimeID {runtime_id}, expected {expected['runtimeID']}."})
        if runtime_type != expected["runtimeType"]:
            issues.append({"severity": "error", "message": f"Speech asset {asset_id} declares runtimeType {runtime_type}, expected {expected['runtimeType']}."})
        expected_locale = expected.get("locale")
        if expected_locale and locale and locale.lower() != expected_locale.lower():
            issues.append({"severity": "error", "message": f"Speech asset {asset_id} declares locale {locale}, expected {expected['locale']}."})
        expected_voice_bundle_id = expected.get("voiceBundleID")
        if expected_voice_bundle_id and voice_bundle_id != expected_voice_bundle_id:
            issues.append({"severity": "error", "message": f"Speech asset {asset_id} declares voiceBundleID {voice_bundle_id}, expected {expected_voice_bundle_id}."})
        expected_supported_voice_bundle_ids = expected.get("supportedVoiceBundleIDs") or []
        if expected_supported_voice_bundle_ids:
            missing_voice_bundle_ids = sorted(set(expected_supported_voice_bundle_ids).difference(supported_voice_bundle_ids or ([voice_bundle_id] if voice_bundle_id else [])))
            if missing_voice_bundle_ids:
                issues.append({"severity": "error", "message": f"Speech asset {asset_id} is missing supported voice bundles: {', '.join(missing_voice_bundle_ids)}."})
        if asset_path.exists() is False:
            issues.append({"severity": "error", "message": f"Speech asset payload for {asset_id} is missing at {asset_path}."})
            continue

        if asset_path.is_dir():
            actual_size = sum(child.stat().st_size for child in asset_path.rglob("*") if child.is_file())
            digest = hashlib.sha256()
            for child in sorted(p for p in asset_path.rglob("*") if p.is_file()):
                digest.update(child.relative_to(asset_path).as_posix().encode("utf-8"))
                digest.update(b"\0")
                digest.update(hashlib.sha256(child.read_bytes()).hexdigest().encode("utf-8"))
                digest.update(b"\0")
            actual_checksum = digest.hexdigest()
        else:
            actual_size = asset_path.stat().st_size
            actual_checksum = hashlib.sha256(asset_path.read_bytes()).hexdigest()

        expected_size = asset.get("size")
        expected_checksum = str(asset.get("checksum") or "").strip()
        if expected_size not in (None, "") and actual_size != int(expected_size):
            issues.append({"severity": "error", "message": f"Speech asset {asset_id} has size {actual_size} bytes, expected {expected_size} bytes."})
        if expected_checksum and actual_checksum != expected_checksum:
            issues.append({"severity": "error", "message": f"Speech asset {asset_id} checksum mismatch."})

if runtime_build_path.exists() is False:
    issues.append({"severity": "error", "message": f"Missing runtime build facts at {runtime_build_path}"})
else:
    runtime_build = json.loads(runtime_build_path.read_text(encoding="utf-8"))
    expected_truths = {
        "sherpaOnnxEnabled": True,
        "kokoroEnabled": True,
        "sherpaOnnxBridgeLinked": True,
        "kokoroBridgeLinked": True,
    }
    for key, expected_value in expected_truths.items():
        if bool(runtime_build.get(key)) is not expected_value:
            issues.append({"severity": "error", "message": f"Runtime build fact {key} is {runtime_build.get(key)!r}, expected {expected_value!r}."})

payload = {
    "generatedAt": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat(),
    "embeddedModelIDs": embedded_model_ids,
    "speechAssetIDs": speech_asset_ids,
    "issues": issues,
}

report_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
legacy_report_path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

if any(issue["severity"].lower() == "error" for issue in issues):
    sys.exit(1)
PY

echo "Bundle audit report written to ${REPORT_PATH}" >&2
