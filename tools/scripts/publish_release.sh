#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 --release-dir <path> --target-repo-dir <path> [options]

Options:
  --target-branch <name>      Branch to publish to (default: main)
  --target-repo-url <url>     Clone URL if target repo dir does not exist
  --commit <bool>             Create commit (default: true)
  --push <bool>               Push commit (default: false)
  --delete <bool>             Delete removed files in target road-index dir (default: true)
  --help
USAGE
}

RELEASE_DIR=""
TARGET_REPO_DIR=""
TARGET_BRANCH="main"
TARGET_REPO_URL=""
DO_COMMIT="true"
DO_PUSH="false"
DO_DELETE="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release-dir) RELEASE_DIR="$2"; shift 2 ;;
    --target-repo-dir) TARGET_REPO_DIR="$2"; shift 2 ;;
    --target-branch) TARGET_BRANCH="$2"; shift 2 ;;
    --target-repo-url) TARGET_REPO_URL="$2"; shift 2 ;;
    --commit) DO_COMMIT="$2"; shift 2 ;;
    --push) DO_PUSH="$2"; shift 2 ;;
    --delete) DO_DELETE="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$RELEASE_DIR" || -z "$TARGET_REPO_DIR" ]]; then
  echo "--release-dir and --target-repo-dir are required"
  usage
  exit 1
fi

if [[ ! -d "$RELEASE_DIR" ]]; then
  echo "Release dir not found: $RELEASE_DIR"
  exit 1
fi

SOURCE_ROOT="$RELEASE_DIR/publish/road-index"
MANIFEST_PATH="$RELEASE_DIR/manifest.json"
REPORT_PATH="$RELEASE_DIR/build_report.json"

if [[ ! -d "$SOURCE_ROOT" ]]; then
  echo "Missing source publish root: $SOURCE_ROOT"
  exit 1
fi

if [[ ! -f "$MANIFEST_PATH" || ! -f "$REPORT_PATH" ]]; then
  echo "Missing manifest/report in release dir"
  exit 1
fi

if [[ ! -d "$TARGET_REPO_DIR/.git" ]]; then
  if [[ -n "$TARGET_REPO_URL" ]]; then
    echo "Cloning target repo into $TARGET_REPO_DIR"
    git clone "$TARGET_REPO_URL" "$TARGET_REPO_DIR"
  else
    echo "Target repo missing and no --target-repo-url provided: $TARGET_REPO_DIR"
    exit 1
  fi
fi

git -C "$TARGET_REPO_DIR" fetch origin "$TARGET_BRANCH"
git -C "$TARGET_REPO_DIR" checkout "$TARGET_BRANCH"
git -C "$TARGET_REPO_DIR" pull --ff-only origin "$TARGET_BRANCH"

mkdir -p "$TARGET_REPO_DIR/road-index"

rsync_args=( -a )
if [[ "$DO_DELETE" == "true" ]]; then
  rsync_args+=( --delete )
fi

rsync "${rsync_args[@]}" "$SOURCE_ROOT/" "$TARGET_REPO_DIR/road-index/"
cp "$MANIFEST_PATH" "$TARGET_REPO_DIR/road-index/manifest.json"
cp "$REPORT_PATH" "$TARGET_REPO_DIR/road-index/build_report.json"

if [[ "$DO_COMMIT" == "true" ]]; then
  git -C "$TARGET_REPO_DIR" add road-index
  if ! git -C "$TARGET_REPO_DIR" diff --cached --quiet; then
    release_id="$(basename "$RELEASE_DIR")"
    git -C "$TARGET_REPO_DIR" commit -m "data: publish $release_id"
  else
    echo "No publish changes to commit"
  fi
fi

if [[ "$DO_PUSH" == "true" ]]; then
  git -C "$TARGET_REPO_DIR" push origin "$TARGET_BRANCH"
fi

echo "publish_release completed"
