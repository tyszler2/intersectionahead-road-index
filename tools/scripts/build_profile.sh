#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage: $0 --profile <profile_id> [options]

Options:
  --config <path>             Coverage profiles YAML (default: tools/config/coverage_profiles.yaml)
  --work-root <path>          Working release root (default: .build/data)
  --rebuild-scope <value>     all or comma-separated shard ids (default: all)
  --download-missing <bool>   true/false (default: true)
  --legacy-layout <bool>      true/false copy per-shard regions into publish root (default: true)
  --help
USAGE
}

PROFILE=""
CONFIG_PATH="tools/config/coverage_profiles.yaml"
WORK_ROOT=".build/data"
REBUILD_SCOPE="all"
DOWNLOAD_MISSING="true"
LEGACY_LAYOUT="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --profile) PROFILE="$2"; shift 2 ;;
    --config) CONFIG_PATH="$2"; shift 2 ;;
    --work-root) WORK_ROOT="$2"; shift 2 ;;
    --rebuild-scope) REBUILD_SCOPE="$2"; shift 2 ;;
    --download-missing) DOWNLOAD_MISSING="$2"; shift 2 ;;
    --legacy-layout) LEGACY_LAYOUT="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown arg: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$PROFILE" ]]; then
  echo "--profile is required"
  usage
  exit 1
fi

if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "Config not found: $CONFIG_PATH"
  exit 1
fi

BUILD_REGION_SCRIPT="tools/scripts/build_region.sh"
BUILDER_BIN="tools/road_index_builder/target/release/road_index_builder"

if [[ ! -x "$BUILD_REGION_SCRIPT" ]]; then
  echo "Missing executable: $BUILD_REGION_SCRIPT"
  exit 1
fi

if [[ ! -x "$BUILDER_BIN" ]]; then
  echo "Missing builder binary: $BUILDER_BIN"
  echo "Run: cargo build --release --manifest-path tools/road_index_builder/Cargo.toml"
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

RELEASE_REGION_ID="$(profile_scalar release_region_id)"
OUTPUT_NAMESPACE="$(profile_scalar output_namespace)"
PACK_VERSION="$(profile_scalar pack_version)"

if [[ -z "$RELEASE_REGION_ID" || -z "$OUTPUT_NAMESPACE" || -z "$PACK_VERSION" ]]; then
  echo "Profile not found or incomplete: $PROFILE"
  exit 1
fi

SHARDS=()
while IFS= read -r line; do
  SHARDS+=("$line")
done < <(profile_list shards)
if [[ ${#SHARDS[@]} -eq 0 ]]; then
  echo "No shards found for profile: $PROFILE"
  exit 1
fi

SEAM_TILES=()
while IFS= read -r line; do
  SEAM_TILES+=("$line")
done < <(profile_list seam_tiles)

RELEASE_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RELEASE_DIR="$WORK_ROOT/releases/$RELEASE_ID"
mkdir -p "$RELEASE_DIR/shards" "$RELEASE_DIR/publish/$OUTPUT_NAMESPACE/$RELEASE_REGION_ID"

SHARD_META_TSV="$RELEASE_DIR/shards.tsv"
SEAM_TILES_FILE="$RELEASE_DIR/seam_tiles.txt"
: > "$SHARD_META_TSV"
: > "$SEAM_TILES_FILE"

for seam in "${SEAM_TILES[@]}"; do
  echo "$seam" >> "$SEAM_TILES_FILE"
done

FILTER_CSV=""
if [[ "$REBUILD_SCOPE" != "all" ]]; then
  IFS=',' read -r -a FILTER_IDS <<< "$REBUILD_SCOPE"
  FILTER_CSV=","
  for id in "${FILTER_IDS[@]}"; do
    clean="$(echo "$id" | xargs)"
    if [[ -n "$clean" ]]; then
      FILTER_CSV+="$clean,"
    fi
  done
fi

any_built=0

for row in "${SHARDS[@]}"; do
  IFS='|' read -r shard_id source_pbf source_url min_lon min_lat max_lon max_lat <<< "$row"

  if [[ "$REBUILD_SCOPE" != "all" ]]; then
    if [[ "$FILTER_CSV" != *",$shard_id,"* ]]; then
      continue
    fi
  fi

  if [[ -z "$shard_id" || -z "$source_pbf" || -z "$min_lon" || -z "$min_lat" || -z "$max_lon" || -z "$max_lat" ]]; then
    echo "Invalid shard row: $row"
    exit 1
  fi

  if [[ ! -f "$source_pbf" ]]; then
    if [[ "$DOWNLOAD_MISSING" == "true" && -n "$source_url" ]]; then
      echo "Downloading missing PBF for $shard_id -> $source_pbf"
      mkdir -p "$(dirname "$source_pbf")"
      curl -L --fail "$source_url" -o "$source_pbf"
    else
      echo "Missing source PBF for $shard_id: $source_pbf"
      exit 1
    fi
  fi

  out_dir="$RELEASE_DIR/shards"

  echo "Building shard: $shard_id"
  "$BUILD_REGION_SCRIPT" "$shard_id" "$source_pbf" "$min_lon" "$min_lat" "$max_lon" "$max_lat" "$out_dir"

  shard_dir="$RELEASE_DIR/shards/$shard_id"
  if [[ ! -d "$shard_dir" ]]; then
    echo "Expected shard output dir missing: $shard_dir"
    exit 1
  fi

  shard_chunk_count="$(find "$shard_dir" -type f -name '*.iarc' | wc -l | tr -d ' ')"
  source_size="$(stat -f '%z' "$source_pbf")"
  source_mtime="$(stat -f '%m' "$source_pbf")"

  if [[ "$LEGACY_LAYOUT" == "true" ]]; then
    mkdir -p "$RELEASE_DIR/publish/$OUTPUT_NAMESPACE/$shard_id"
    rsync -a "$shard_dir/" "$RELEASE_DIR/publish/$OUTPUT_NAMESPACE/$shard_id/"
  fi

  rsync -a "$shard_dir/" "$RELEASE_DIR/publish/$OUTPUT_NAMESPACE/$RELEASE_REGION_ID/"

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$shard_id" "$source_pbf" "$source_size" "$source_mtime" "$min_lon" "$min_lat" "$max_lon" "$max_lat" "$shard_chunk_count" \
    >> "$SHARD_META_TSV"

  any_built=1
done

if [[ $any_built -eq 0 ]]; then
  echo "No shards built for scope: $REBUILD_SCOPE"
  exit 1
fi

python3 - "$RELEASE_DIR" "$PROFILE" "$OUTPUT_NAMESPACE" "$RELEASE_REGION_ID" "$PACK_VERSION" "$SHARD_META_TSV" <<'PY'
import csv
import datetime as dt
import hashlib
import json
import os
import pathlib
import struct
import sys

release_dir = pathlib.Path(sys.argv[1])
profile = sys.argv[2]
output_namespace = sys.argv[3]
release_region_id = sys.argv[4]
pack_version = int(sys.argv[5])
meta_tsv = pathlib.Path(sys.argv[6])

rows = []
with meta_tsv.open("r", encoding="utf-8") as f:
    reader = csv.reader(f, delimiter="\t")
    for r in reader:
        if not r:
            continue
        rows.append({
            "shard_id": r[0],
            "source_pbf": r[1],
            "source_size": int(r[2]),
            "source_mtime": int(r[3]),
            "min_lon": float(r[4]),
            "min_lat": float(r[5]),
            "max_lon": float(r[6]),
            "max_lat": float(r[7]),
            "chunk_count": int(r[8]),
        })

publish_root = release_dir / "publish" / output_namespace
seam_tiles_path = release_dir / "seam_tiles.txt"

def list_chunks(d: pathlib.Path):
    if not d.exists():
        return []
    return sorted(p for p in d.rglob("*.iarc") if p.is_file())

def dir_digest(paths):
    h = hashlib.sha256()
    for p in paths:
        rel = p.as_posix().encode("utf-8")
        h.update(rel)
        h.update(b"\0")
        with p.open("rb") as fh:
            for chunk in iter(lambda: fh.read(1024 * 1024), b""):
                h.update(chunk)
    return h.hexdigest()

def read_u16(buf, off):
    return struct.unpack_from("<H", buf, off)[0], off + 2

def read_u32(buf, off):
    return struct.unpack_from("<I", buf, off)[0], off + 4

def read_i32(buf, off):
    return struct.unpack_from("<i", buf, off)[0], off + 4

def read_i16(buf, off):
    return struct.unpack_from("<h", buf, off)[0], off + 2

def read_f64(buf, off):
    return struct.unpack_from("<d", buf, off)[0], off + 8

def read_f32(buf, off):
    return struct.unpack_from("<f", buf, off)[0], off + 4

def parse_chunk_metrics(path):
    data = path.read_bytes()
    if data[:4] != b"IARC":
        raise ValueError("bad container magic")
    off = 4
    _, off = read_u16(data, off)  # version
    compression, off = read_u16(data, off)
    payload_size, off = read_u32(data, off)
    if compression != 0:
        raise ValueError("unsupported compression")
    payload = memoryview(data)[off:off + payload_size]
    off = 0
    if payload[:4].tobytes() != b"IAR1":
        raise ValueError("bad payload magic")
    off += 4
    version, off = read_u16(payload, off)
    _, off = read_u16(payload, off)
    _, off = read_f64(payload, off)  # origin lat
    _, off = read_f64(payload, off)  # origin lon
    _, off = read_f32(payload, off)  # cell size
    _, off = read_u16(payload, off)  # grid w
    _, off = read_u16(payload, off)  # grid h
    strings_count, off = read_u32(payload, off)
    nodes_count, off = read_u32(payload, off)
    segments_count, off = read_u32(payload, off)
    shapes_count, off = read_u32(payload, off)
    node_edges_count, off = read_u32(payload, off)
    cell_entries_count, off = read_u32(payload, off)
    cell_segments_count, off = read_u32(payload, off)
    string_bytes, off = read_u32(payload, off)
    junctions_count = 0
    services_count = 0
    if version >= 2:
        junctions_count, off = read_u32(payload, off)
        services_count, off = read_u32(payload, off)

    string_offsets = []
    for _ in range(strings_count + 1):
        v, off = read_u32(payload, off)
        string_offsets.append(v)
    string_blob = payload[off:off + string_bytes].tobytes()
    off += string_bytes

    strings = []
    for i in range(strings_count):
        start = string_offsets[i]
        end = string_offsets[i + 1]
        if start >= end or end > len(string_blob):
            strings.append("")
            continue
        s = string_blob[start:end].decode("utf-8", errors="replace")
        strings.append(s)

    # nodes
    off += nodes_count * 16

    named_segments = 0
    for _ in range(segments_count):
        name_idx, off = read_u32(payload, off)
        if name_idx < len(strings):
            if strings[name_idx].strip():
                named_segments += 1
        off += 4 + 4 + 4 + 2 + 2 + 2  # nodeA,nodeB,shapeStart,shapeCount,flags,bearingAB
        off += 2  # bearingBA

    off += shapes_count * 8
    off += node_edges_count * 4
    off += cell_entries_count * 12
    off += cell_segments_count * 4

    junction_ref = 0
    for _ in range(junctions_count):
        off += 4 + 4 + 4  # lat, lon, seg
        ref_idx, off = read_u32(payload, off)
        off += 4 + 4  # name_idx, dest_idx
        off += 2 + 2  # padding
        if ref_idx < len(strings) and strings[ref_idx].strip():
            junction_ref += 1

    service_counts = {}
    for _ in range(services_count):
        off += 4 + 4 + 4  # lat, lon, seg
        kind, off = read_u16(payload, off)
        off += 4  # name_idx
        off += 2  # padding
        service_counts[kind] = service_counts.get(kind, 0) + 1

    return {
        "segments_count": segments_count,
        "named_segments": named_segments,
        "junctions_count": junctions_count,
        "junction_ref": junction_ref,
        "service_counts": service_counts,
    }

region_entries = []
for region_dir in sorted([p for p in publish_root.iterdir() if p.is_dir()]):
    chunks = list_chunks(region_dir)
    region_entries.append({
        "id": region_dir.name,
        "chunk_count": len(chunks),
        "checksum_sha256": dir_digest(chunks),
    })

utc_now = dt.datetime.now(dt.timezone.utc)
release_id = release_dir.name

metric_segments = 0
metric_named_segments = 0
metric_junctions = 0
metric_junction_ref = 0
metric_service_counts = {}

if seam_tiles_path.exists():
    for line in seam_tiles_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            region, z, x, y = line.split("|")
        except ValueError:
            continue
        chunk_path = publish_root / region / z / x / f"{y}.iarc"
        if not chunk_path.exists():
            continue
        try:
            m = parse_chunk_metrics(chunk_path)
        except Exception:
            continue
        metric_segments += m["segments_count"]
        metric_named_segments += m["named_segments"]
        metric_junctions += m["junctions_count"]
        metric_junction_ref += m["junction_ref"]
        for k, v in m["service_counts"].items():
            metric_service_counts[k] = metric_service_counts.get(k, 0) + v

named_rate = None
junction_ref_rate = None
if metric_segments > 0:
    named_rate = metric_named_segments / metric_segments
if metric_junctions > 0:
    junction_ref_rate = metric_junction_ref / metric_junctions

manifest = {
    "release_id": release_id,
    "generated_at": utc_now.isoformat(),
    "coverage_profile": profile,
    "pack_version": pack_version,
    "output_namespace": output_namespace,
    "release_region_id": release_region_id,
    "regions": region_entries,
    "tile_counts": {e["id"]: e["chunk_count"] for e in region_entries},
    "checksums": {e["id"]: e["checksum_sha256"] for e in region_entries},
    "source_pbf_versions": {
        row["shard_id"]: {
            "path": row["source_pbf"],
            "size_bytes": row["source_size"],
            "mtime_epoch": row["source_mtime"],
        }
        for row in rows
    },
    "shards": rows,
}

build_report = {
    "release_id": release_id,
    "generated_at": utc_now.isoformat(),
    "coverage_profile": profile,
    "summary": {
        "shards_built": len(rows),
        "regions_published": len(region_entries),
        "total_chunks": sum(e["chunk_count"] for e in region_entries),
    },
    "regression_metrics": {
        "metrics_scope": "seam_tiles_sample",
        "named_segment_fill_rate": named_rate,
        "junction_ref_fill_rate": junction_ref_rate,
        "service_count_by_kind": metric_service_counts or None,
    },
    "checks": {
        "chunk_presence": "pending_verify_release",
        "sample_decode": "pending_verify_release",
        "seam_tiles": "pending_verify_release",
        "http_headers": "pending_verify_release",
    },
}

(manifest_path := release_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
(report_path := release_dir / "build_report.json").write_text(json.dumps(build_report, indent=2) + "\n", encoding="utf-8")

latest_ptr = release_dir.parent / "latest_release_path.txt"
latest_ptr.write_text(str(release_dir) + "\n", encoding="utf-8")

print(str(release_dir))
PY
