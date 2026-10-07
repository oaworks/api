#!/usr/bin/env bash

set -euo pipefail

DEFAULT_URL="https://static.oa.works"
BASE_URL=""
TARGET_IP=""
TARGET_IP_CONFIRMED=0
IDENTITY_FILE=""
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FIXTURES_DIR="${SCRIPT_DIR}/../fixtures"

usage() {
  echo "Usage: $0 [-u|--url <base_url>] [-i|--ip <ip_address>] [-k|--key <private_key>]"
  echo "  -u, --url   Base URL to fetch fixtures from (default: ${DEFAULT_URL})"
  echo "  -i, --ip    Run on the specified droplet IP (as oaw, in ~/api)"
  echo "  -k, --key   SSH private key for the remote connection (prompted if omitted with --ip)"
  exit "${1:-1}"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -u|--url)
      if [ $# -lt 2 ]; then
        echo "Error: $1 requires a URL." >&2
        usage
      fi
      BASE_URL="$2"
      shift 2
      ;;
    -i|--ip)
      TARGET_IP="$2"
      shift 2
      ;;
    -k|--key)
      IDENTITY_FILE="$2"
      shift 2
      ;;
    --target-ip-confirmed)
      TARGET_IP_CONFIRMED=1
      shift
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

if [ -z "$TARGET_IP" ] && [ "$TARGET_IP_CONFIRMED" -eq 0 ]; then
  read -r -p "Get fixtures on this local machine? [Y/n]: " RUN_LOCAL_CHOICE
  if [[ ! "${RUN_LOCAL_CHOICE:-Y}" =~ ^[Yy]$ ]]; then
    echo "Cancelled. To run on a remote server, use -i/--ip <ip_address>."
    exit 0
  fi
fi

if [ -n "$TARGET_IP" ]; then
  SSH_OPTS=(-t -o StrictHostKeyChecking=accept-new -o BatchMode=yes)
  if [ -z "$IDENTITY_FILE" ]; then
    IDENTITY_FILES=()
    for candidate in "$HOME"/.ssh/*; do
      [ -f "$candidate" ] || continue
      candidate_name="${candidate##*/}"
      case "$candidate_name" in
        *.pub|config|known_hosts|known_hosts.old|authorized_keys|authorized_keys2|environment) continue ;;
      esac
      IDENTITY_FILES+=("$candidate")
    done

    DEFAULT_IDENTITY_INDEX=""
    for preferred_name in id_ed25519 id_ecdsa id_rsa id_ed25519_sk id_ecdsa_sk; do
      for index in "${!IDENTITY_FILES[@]}"; do
        if [ "${IDENTITY_FILES[$index]##*/}" = "$preferred_name" ]; then
          DEFAULT_IDENTITY_INDEX="$index"
          break 2
        fi
      done
    done

    SUGGESTED_IDENTITY_FILE=""
    if [ -n "$DEFAULT_IDENTITY_INDEX" ]; then
      SUGGESTED_IDENTITY_FILE="${IDENTITY_FILES[$DEFAULT_IDENTITY_INDEX]}"
    fi
    if [ "${#IDENTITY_FILES[@]}" -gt 0 ]; then
      echo "Available local SSH private keys:"
      printf '  %s\n' "${IDENTITY_FILES[@]}"
    fi
    read -r -p "Path to SSH private key${SUGGESTED_IDENTITY_FILE:+ [$SUGGESTED_IDENTITY_FILE]}: " IDENTITY_FILE
    IDENTITY_FILE="${IDENTITY_FILE:-$SUGGESTED_IDENTITY_FILE}"
  fi

  case "$IDENTITY_FILE" in
    "~/"*) IDENTITY_FILE="$HOME/${IDENTITY_FILE:2}" ;;
  esac
  if [ -z "$IDENTITY_FILE" ] || [ ! -f "$IDENTITY_FILE" ]; then
    echo "Error: A valid SSH private key file path is required." >&2
    exit 1
  fi
  SSH_OPTS+=(-i "$IDENTITY_FILE" -o IdentitiesOnly=yes)

  REMOTE_COMMAND='cd ~/api && bash ./scripts/get_fixtures.sh --target-ip-confirmed'
  [ -n "$BASE_URL" ] && printf -v REMOTE_COMMAND '%s --url %q' "$REMOTE_COMMAND" "$BASE_URL"
  echo "Running get_fixtures.sh on droplet (${TARGET_IP})..."
  exec ssh "${SSH_OPTS[@]}" "oaw@${TARGET_IP}" "$REMOTE_COMMAND"
fi

if [ -z "$BASE_URL" ]; then
  BASE_URL="$DEFAULT_URL"
  echo "Using default URL '${BASE_URL}'. To change it, use -u/--url <base_url>."
fi
BASE_URL="${BASE_URL%/}"

for cmd in curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: Required command '$cmd' is not installed." >&2
    exit 1
  fi
done

no_fixtures() {
  echo "There are no fixtures available at ${BASE_URL}/fixtures."
  echo "Re-run this script with -u/--url <base_url> of a running instance of the API that has generated fixtures already."
  exit 0
}

META=$(curl -fsS "${BASE_URL}/fixtures/_meta.json" 2>/dev/null) || no_fixtures
if ! jq -e 'type == "object" and has("finished") and .finished != null' <<< "$META" >/dev/null 2>&1; then
  no_fixtures
fi

# Each dump dataset is recorded in _meta.json as a numeric count keyed by its name.
mapfile -t DATASETS < <(jq -r 'to_entries[] | select(.key | IN("started", "restarted", "finished", "break") | not) | select(.value | type == "number") | .key' <<< "$META")

mkdir -p "$FIXTURES_DIR"
FIXTURES_DIR=$(cd "$FIXTURES_DIR" && pwd)

FILES=(_meta.json)
for dataset in "${DATASETS[@]}"; do
  if [[ ! "$dataset" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "Warning: Skipping unexpected fixture name '${dataset}'." >&2
    continue
  fi
  FILES+=("${dataset}.jsonl")
done

echo "Downloading fixtures from ${BASE_URL}/fixtures into ${FIXTURES_DIR}..."
for file in "${FILES[@]}"; do
  echo "Retrieving ${file}..."
  curl -fsS "${BASE_URL}/fixtures/${file}" -o "${FIXTURES_DIR}/${file}"
done

echo "Done: ${#FILES[@]} fixture file(s) saved to ${FIXTURES_DIR}."
