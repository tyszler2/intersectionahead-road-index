#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 --release-dir <path> --profile <profile_id> [options]

Options:
  --config <path>             Coverage profiles YAML (default: tools/config/coverage_profiles.yaml)
  --sample-decodes <n>        Number of local seam tiles to decode (default: 3)
  --remote-base-url <url>     Optional remote base URL (example: https://.../road-index)
  --require-remote <bool>     If true, fail when remote checks fail (default: false)
  --help
USAGE
}

RELEASE_DIR=""
PROFILE=""
CONFIG_PATH="tools/config/coverage_profiles.yaml"
SAMPLE_DECODES=3
REMOTE_BASE_URL=""
REQUIRE_REMOTE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-dir) RELEASE_DIR="$2"; shift 2 ;;
    --profile) PROFILE="$2"; shift 2 ;;
    --config) CONFIG_PATH="$2"; shift 2 ;;
    --sample-decodes) SAMPLE_DECODES="$2"; shift 2 ;;
    --remote-base-url) REMOTE_BASE_URL="$2"; shift 2 ;;
    --require-remote) REQUIRE_REMOTE="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$RELEASE_DIR" || -z "$PROFILE" ]]; then
  echo "--release-dir and --profile are required"
  usage
  exit 1
fi

if [[ ! -d "$RELEASE_DIR" ]]; then
  echo "Release dir not found: $RELEASE_DIR"
  exit 1
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "Config not found: $CONFIG_PATH"
  exit 1
fi

profile_scalar() {
  local key="$1"
  awk -v p="$PROFILE" -v k="$key" '
    $0 ~ "^  " p ":" {in_profile=1; next}
    in_profile && $0 ~ "^  [a-zA-Z0-9_]+:" {in_profile=0}
    in_profile && $0 ~ "^    " k ":" {
      sub("^    " k ":[[:space:]]*", "", $0)
      print $0
      exit
    }
  ' "$CONFIG_PATH"
}

profile_list() {
  local key="$1"
  awk -v p="$PROFILE" -v k="$key" '
    $0 ~ "^  " p ":" {in_profile=1; next}
    in_profile && $0 ~ "^  [a-zA-Z0-9_]+:" {in_profile=0}
    in_profile && $0 ~ "^    " k ":" {in_list=1; next}
    in_profile && in_list && $0 ~ "^      - " {
      line=$0
      sub("^      - ", "", line)
      print line
      next
    }
    in_profile && in_list && $0 !~ "^      - " {in_list=0}
  ' "$CONFIG_PATH"
}

OUTPUT_NAMESPACE="$(profile_scalar output_namespace)"
RELEASE_REGION_ID="$(profile_scalar release_region_id)"

if [[ -z "$OUTPUT_NAMESPACE" || -z "$RELEASE_REGION_ID" ]]; then
  echo "Profile not found or incomplete: $PROFILE"
  exit 1
fi

SEAM_TILES=()
while IFS= read -r line; do
  SEAM_TILES+=("$line")
done < <(profile_list seam_tiles)
if [[ ${#SEAM_TILES[@]} -eq 0 ]]; then
  echo "No seam tiles defined for profile: $PROFILE"
  exit 1
fi

PUBLISH_ROOT="$RELEASE_DIR/publish/$OUTPUT_NAMESPACE"
if [[ ! -d "$PUBLISH_ROOT" ]]; then
  echo "Missing publish root: $PUBLISH_ROOT"
  exit 1
fi

missing=0
checked=0

decode_candidates=()

for seam in "${SEAM_TILES[@]}"; do
  IFS='|' read -r region z x y <<< "$seam"
  path="$PUBLISH_ROOT/$region/$z/$x/$y.iarc"
  checked=$((checked + 1))
  if [[ ! -f "$path" ]]; then
    echo "MISSING seam tile: $path"
    missing=$((missing + 1))
    continue
  fi

  magic="$(xxd -p -l 4 "$path" | tr -d '\n')"
  if [[ "$magic" != "49415243" ]]; then
    echo "INVALID header magic (expected IARC): $path"
    missing=$((missing + 1))
    continue
  fi

  decode_candidates+=("$path")
done

if [[ $missing -gt 0 ]]; then
  echo "Local seam/header checks failed: $missing/$checked"
  exit 1
fi

effective_decodes=$SAMPLE_DECODES
if [[ ${#decode_candidates[@]} -lt $effective_decodes ]]; then
  effective_decodes=${#decode_candidates[@]}
fi

for ((i=0; i<effective_decodes; i++)); do
  chunk="${decode_candidates[$i]}"
  if ! SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$PWD/.build/modulecache}" \
       CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/modulecache}" \
       swift run RoadIndexCLI --chunk "$chunk" --lat 40.0 --lon -74.0 >/tmp/verify_release_decode_$i.log 2>&1; then
    echo "Sample decode failed for: $chunk"
    sed -n '1,120p' "/tmp/verify_release_decode_$i.log" || true
    exit 1
  fi
done

if [[ -n "$REMOTE_BASE_URL" ]]; then
  remote_fail=0
  for seam in "${SEAM_TILES[@]}"; do
    IFS='|' read -r region z x y <<< "$seam"
    url="$REMOTE_BASE_URL/$region/$z/$x/$y.iarc"
    headers="$(curl -I -s "$url" || true)"
    if ! echo "$headers" | rg -q "^HTTP/.* 200"; then
      echo "Remote missing/non-200: $url"
      remote_fail=$((remote_fail + 1))
      continue
    fi
    if ! echo "$headers" | rg -qi "content-length:"; then
      echo "Remote header missing content-length: $url"
      remote_fail=$((remote_fail + 1))
      continue
    fi
  done
  if [[ $remote_fail -gt 0 ]]; then
    if [[ "$REQUIRE_REMOTE" == "true" ]]; then
      echo "Remote checks failed: $remote_fail"
      exit 1
    fi
    echo "Remote checks reported failures but not required: $remote_fail"
  fi
fi

echo "verify_release passed"
