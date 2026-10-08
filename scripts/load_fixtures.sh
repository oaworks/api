#!/usr/bin/env bash

set -euo pipefail

DEFAULT_URL="http://localhost:4000/fixtures/load?trigger"
TRIGGER_URL=""
TARGET_IP=""
TARGET_IP_CONFIRMED=0
IDENTITY_FILE=""
EMPTY_MODE=0
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
FIXTURES_DIR="${SCRIPT_DIR}/../fixtures"
API_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
INJECTED_FILE="${API_DIR}/server/src/fixtures_load.coffee"

usage() {
  echo "Usage: $0 [-u|--url <trigger_url>] [-i|--ip <ip_address>] [-k|--key <private_key>]"
  echo "  -u, --url   Fixtures load trigger URL (default: ${DEFAULT_URL})"
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
      TRIGGER_URL="$2"
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
    --EMPTY)
      EMPTY_MODE=1
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
  read -r -p "Target VM IP address (leave blank to load fixtures locally): " TARGET_IP
fi

if [ -z "$TARGET_IP" ] && [ "$TARGET_IP_CONFIRMED" -eq 0 ]; then
  read -r -p "Load fixtures on this local machine? [y/N]: " RUN_LOCAL_CHOICE
  if [[ ! "${RUN_LOCAL_CHOICE:-N}" =~ ^[Yy]$ ]]; then
    echo "Cancelled. To run on a remote server, use -i/--ip <ip_address>."
    exit 0
  fi
fi

if [ -n "$TARGET_IP" ]; then
  # -t gives the remote run a terminal so its Y/n prompt is shown.
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

  REMOTE_COMMAND='cd ~/api && bash ./scripts/load_fixtures.sh --target-ip-confirmed'
  [ -n "$TRIGGER_URL" ] && printf -v REMOTE_COMMAND '%s --url %q' "$REMOTE_COMMAND" "$TRIGGER_URL"
  [ "$EMPTY_MODE" -eq 1 ] && REMOTE_COMMAND+=' --EMPTY'
  echo "Running load_fixtures.sh on droplet (${TARGET_IP})..."
  exec ssh "${SSH_OPTS[@]}" "oaw@${TARGET_IP}" "$REMOTE_COMMAND"
fi

if [ ! -d "$FIXTURES_DIR" ] || [ -z "$(find "$FIXTURES_DIR" -mindepth 1 -maxdepth 1 -type f -print -quit)" ]; then
  echo "No fixture files found in ${FIXTURES_DIR}."
  echo "Run get_fixtures.sh, or populate that folder in your preferred way, then rerun this script."
  exit 1
fi

TRIGGER_URL="${TRIGGER_URL:-$DEFAULT_URL}"
if [ "$EMPTY_MODE" -eq 1 ]; then
  case "$TRIGGER_URL" in
    *\?*|*\&*)
      case "$TRIGGER_URL" in
        *\?|*\&) TRIGGER_URL="${TRIGGER_URL}clear=true" ;;
        *) TRIGGER_URL="${TRIGGER_URL}&clear=true" ;;
      esac
      ;;
    *) TRIGGER_URL="${TRIGGER_URL}?clear=true" ;;
  esac
fi
echo "Fixture files found in $(cd "$FIXTURES_DIR" && pwd)."
echo ""
echo "This script assumes you are running a dev instance of the API,"
echo "and that it has been configured to connect to an OpenSearch instance,"
echo "and it is running the default npm run start (node --watch) instance."
echo "If not, this script will fail."
echo "(This script could configure and turn on the local API...)"
echo "(For the purpose of dev learning that is left as a task for the user.)"
echo ""
echo "A fixture loader will be injected into the API code."
echo "Then the code will be rebuilt with the injected fixtures loader."
echo "(the --watch flag on the API instance then causes a reload of the API code)."
echo "Then a load trigger request will be sent to: ${TRIGGER_URL}"
echo "THIS WILL LOAD DATA INTO THE INDEX CONFIGURED FOR THE RUNNING API INSTANCE."
if [ "$EMPTY_MODE" -eq 1 ]; then
  echo ""
  echo "WARNING: EMPTY MODE IS ALSO ENABLED AS YOU SET THE --EMPTY FLAG."
  echo "ANY FIXTURES FILES THAT ARE RUN WILL ALSO FIRST EMPTY THE INDEXES THEY ARE RELEVANT TO BEFORE LOADING!"
fi

echo ""
read -r -p "Confirm you have a running dev instance of the API, configured with an OpenSearch index, and you are ready to send the trigger request now? [Y/n]: " SEND_CHOICE
if [[ ! "${SEND_CHOICE:-Y}" =~ ^[Yy]$ ]]; then
  echo "Trigger request not sent."
  exit 0
fi

remove_injected_code() {
  echo "Removing injected fixtures code and rebuilding..."
  rm -f "$INJECTED_FILE"
  (cd "$API_DIR" && npm run build)
  echo "Removal of injected fixtures codeand rebuild complete."
}

cp "${SCRIPT_DIR}/fixtures_load.coffee" "$INJECTED_FILE"
trap remove_injected_code EXIT # runs when the script exits, ensuring cleanup
echo "Building the API with the fixtures code..."
(cd "$API_DIR" && npm run build)
echo "Fixtures code has been injected."

# Without ?trigger the new route only returns a note, proving the rebuilt API is live.
READY_URL="${TRIGGER_URL%%\?*}"
echo "Waiting for the API to restart with the fixtures code..."
API_READY=0
for attempt in {1..30}; do
  if curl -fsS --max-time 5 "$READY_URL" 2>/dev/null | grep -q "Fixtures can only be loaded"; then
    API_READY=1
    break
  fi
  sleep 2
done
if [ "$API_READY" -ne 1 ]; then
  echo "Error: The API did not serve the fixtures code at ${READY_URL}. Check that it is running with 'npm run start' (node --watch)." >&2
  exit 1
fi

echo "Sending trigger request..."
if ! RESPONSE=$(curl -fsS "$TRIGGER_URL"); then
  echo "Error: The trigger request to ${TRIGGER_URL} failed." >&2
  exit 1
fi

echo "Response:"
if command -v jq >/dev/null 2>&1 && jq . <<< "$RESPONSE" 2>/dev/null; then
  :
else
  echo "$RESPONSE"
fi
