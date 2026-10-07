#!/usr/bin/env bash

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration & Defaults
# -----------------------------------------------------------------------------
REGION="nyc1"
REGION_PROVIDED=false
IMAGE="ubuntu-26-04-x64"

# Generates timestamped default: e.g., "local202609231621"
DEFAULT_NAME="local$(date +%Y%m%d%H%M)"

DO_TOKEN=""     # Token state tracker
RAM_GB=""       # Left empty to detect if provided via CLI flag
DROPLET_NAME="" # Left empty to detect if provided via CLI flag
DISK_MULT=""    # Disk size multiplier (1x, 3x, 6x) for >=16GB RAM
KEY_FILE=""

# -----------------------------------------------------------------------------
# Parse Command Line Options
# -----------------------------------------------------------------------------
usage() {
  echo "Usage: $0 [-t|--token <api_token>] [-m|--memory <4|8|16|32|64|128|192|256>] [-d|--disk <1x|3x|6x>] [-n|--name <droplet_name>] [-k|--key <private_key>] [-r|--region <slug>]"
  echo "  -t, --token    DigitalOcean API token (prompted if omitted)"
  echo "  -m, --memory   Memory size in GB (default: 4)"
  echo "  -d, --disk     Disk multiplier for >=16GB RAM (1x, 3x, 6x; otherwise 1x)"
  echo "  -n, --name     Droplet name (default: local<timestamp>)"
  echo "  -k, --key      SSH private key file to use when connecting to the new Droplet"
  echo "  -r, --region   DigitalOcean region slug (default: nyc1)"
  echo "  -h, --help     Display this help message"
  exit "${1:-1}"
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -t|--token)
      DO_TOKEN="$2"
      shift 2
      ;;
    -m|--memory)
      RAM_GB="$2"
      shift 2
      ;;
    -d|--disk)
      DISK_MULT="$2"
      shift 2
      ;;
    -n|--name)
      DROPLET_NAME="$2"
      shift 2
      ;;
    -k|--key)
      KEY_FILE="$2"
      shift 2
      ;;
    -r|--region)
      REGION="$2"
      REGION_PROVIDED=true
      shift 2
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

# -----------------------------------------------------------------------------
# Token Resolution Pipeline
# Checks CLI flag -> Interactive Prompt
# -----------------------------------------------------------------------------
if [ -z "$DO_TOKEN" ]; then
  read -sp "Enter your DigitalOcean API Token: " USER_TOKEN_INPUT
  echo ""

  if [ -n "$USER_TOKEN_INPUT" ]; then
    DO_TOKEN="$USER_TOKEN_INPUT"
  fi

  if [ -z "$DO_TOKEN" ]; then
    echo "Error: DigitalOcean API token is required to proceed. Exiting."
    exit 1
  fi
fi

# -----------------------------------------------------------------------------
# Fetch and Select Account SSH Keys
# -----------------------------------------------------------------------------
echo "Fetching SSH keys from DigitalOcean account..."

SSH_KEYS_RESPONSE=$(curl -s -X GET \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${DO_TOKEN}" \
  "https://api.digitalocean.com/v2/account/keys")

KEY_COUNT=$(echo "$SSH_KEYS_RESPONSE" | jq '.ssh_keys | length')
SELECTED_DO_KEY_NAMES=()
SELECTED_DO_KEY_FINGERPRINTS=()
UPLOADED_KEY_FILE=""

# If no keys exist on DO, check for a local public key to upload
if [ -z "$KEY_COUNT" ] || [ "$KEY_COUNT" -eq 0 ]; then
  echo "No SSH keys found in your DigitalOcean account."
  
  # Search for standard local public keys
  LOCAL_PUB_KEY=""
  for key_file in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub" "$HOME/.ssh/id_ecdsa.pub"; do
    if [ -f "$key_file" ]; then
      LOCAL_PUB_KEY="$key_file"
      break
    fi
  done

  if [ -n "$LOCAL_PUB_KEY" ]; then
    echo "Found local SSH key: $LOCAL_PUB_KEY"
    read -p "Would you optionally like to upload this key to DigitalOcean now? [Y/n]: " UPLOAD_CHOICE
    UPLOAD_CHOICE="${UPLOAD_CHOICE:-Y}"

    if [[ "$UPLOAD_CHOICE" =~ ^[Yy]$ ]]; then
      PUB_CONTENT=$(cat "$LOCAL_PUB_KEY")
      KEY_NAME="$(hostname)-$(date +%Y%m%d)"

      echo "Uploading $LOCAL_PUB_KEY as '$KEY_NAME'..."
      
      UPLOAD_PAYLOAD=$(jq -n --arg name "$KEY_NAME" --arg public_key "$PUB_CONTENT" \
        '{name: $name, public_key: $public_key}')
      UPLOAD_RESPONSE=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${DO_TOKEN}" \
        -d "$UPLOAD_PAYLOAD" \
        "https://api.digitalocean.com/v2/account/keys")

      NEW_KEY_ID=$(echo "$UPLOAD_RESPONSE" | jq -r '.ssh_key.id // empty')

      if [ -n "$NEW_KEY_ID" ] && [ "$NEW_KEY_ID" != "null" ]; then
        echo "Successfully uploaded! (Key ID: $NEW_KEY_ID)"
        SSH_KEYS="[$NEW_KEY_ID]"
        SELECTED_KEY_COUNT=1
        SELECTED_DO_KEY_NAMES+=("$KEY_NAME")
        UPLOADED_KEY_FILE="${LOCAL_PUB_KEY%.pub}"
        NEW_FINGERPRINT=$(echo "$UPLOAD_RESPONSE" | jq -r '.ssh_key.fingerprint // empty')
        [ -n "$NEW_FINGERPRINT" ] && SELECTED_DO_KEY_FINGERPRINTS+=("$NEW_FINGERPRINT")
      else
        echo "Failed to upload key:"
        echo "$UPLOAD_RESPONSE" | jq '.message'
        echo "Proceeding without SSH keys, DigitalOcean will send root password via email upon boot."
        SSH_KEYS="[]"
        SELECTED_KEY_COUNT=0
      fi
    else
      SSH_KEYS="[]"
      SELECTED_KEY_COUNT=0
    fi
  else
    echo "No local public keys found in $HOME/.ssh/."
    echo "DigitalOcean will send root password via email upon boot."
    SSH_KEYS="[]"
    SELECTED_KEY_COUNT=0
  fi

else
  echo ""
  echo "Available SSH Keys:"
  
  # Parse keys into arrays for index selection
  mapfile -t KEY_IDS < <(echo "$SSH_KEYS_RESPONSE" | jq -r '.ssh_keys[].id')
  mapfile -t KEY_NAMES < <(echo "$SSH_KEYS_RESPONSE" | jq -r '.ssh_keys[].name')
  mapfile -t KEY_FINGERPRINTS < <(echo "$SSH_KEYS_RESPONSE" | jq -r '.ssh_keys[].fingerprint')

  for i in "${!KEY_NAMES[@]}"; do
    printf "  [%d] %s (%s)\n" "$((i+1))" "${KEY_NAMES[$i]}" "${KEY_FINGERPRINTS[$i]}"
  done

  echo "You can attach keys to the droplet at creation and if you have the matching key you will be able to access it immediately."
  echo "Otherwise DigitalOcean will send the root password via email (to the account email associated with your API token) upon boot."
  read -p "Select key numbers to attach (e.g. '1,3', 'none' to skip, or Enter for ALL): " KEY_CHOICE

  if [[ "$KEY_CHOICE" == "none" || "$KEY_CHOICE" == "0" ]]; then
    SSH_KEYS="[]"
    SELECTED_KEY_COUNT=0
  elif [ -z "$KEY_CHOICE" ]; then
    SSH_KEYS=$(echo "$SSH_KEYS_RESPONSE" | jq -c '[.ssh_keys[].id]')
    SELECTED_KEY_COUNT=$KEY_COUNT
    SELECTED_DO_KEY_NAMES=("${KEY_NAMES[@]}")
    SELECTED_DO_KEY_FINGERPRINTS=("${KEY_FINGERPRINTS[@]}")
  else
    SELECTED_IDS=()
    IFS=',' read -ra CHOICES <<< "$KEY_CHOICE"
    
    for choice in "${CHOICES[@]}"; do
      choice=$(echo "$choice" | xargs)
      if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$KEY_COUNT" ]; then
        INDEX=$((choice-1))
        SELECTED_IDS+=("${KEY_IDS[$INDEX]}")
        SELECTED_DO_KEY_NAMES+=("${KEY_NAMES[$INDEX]}")
        SELECTED_DO_KEY_FINGERPRINTS+=("${KEY_FINGERPRINTS[$INDEX]}")
      else
        echo "Warning: Invalid key selection '$choice' ignored."
      fi
    done

    SSH_KEYS=$(printf '%s\n' "${SELECTED_IDS[@]}" | jq -R . | jq -s -c 'map(toupper | tonumber)')
    SELECTED_KEY_COUNT=${#SELECTED_IDS[@]}
  fi
fi

SSH_KEY_OPTS=()
if [ -n "$KEY_FILE" ]; then
  case "$KEY_FILE" in
    "~/"*) KEY_FILE="$HOME/${KEY_FILE:2}" ;;
  esac
  if [ ! -f "$KEY_FILE" ]; then
    echo "Error: SSH key file '${KEY_FILE}' does not exist." >&2
    exit 1
  fi
else
  KEY_FILES=()
  for candidate in "$HOME"/.ssh/*; do
    [ -f "$candidate" ] || continue
    candidate_name="${candidate##*/}"
    case "$candidate_name" in
      *.pub|config|known_hosts|known_hosts.old|authorized_keys|authorized_keys2|environment) continue ;;
    esac
    KEY_FILES+=("$candidate")
  done

  DEFAULT_KEY_INDEX=""
  if [ -n "$UPLOADED_KEY_FILE" ] && [ -f "$UPLOADED_KEY_FILE" ]; then
    for index in "${!KEY_FILES[@]}"; do
      [ "${KEY_FILES[$index]}" = "$UPLOADED_KEY_FILE" ] && DEFAULT_KEY_INDEX="$index"
    done
  fi

  if [ -z "$DEFAULT_KEY_INDEX" ]; then
    for index in "${!KEY_FILES[@]}"; do
      candidate_name="${KEY_FILES[$index]##*/}"
      for selected_name in "${SELECTED_DO_KEY_NAMES[@]}"; do
        if [ "$candidate_name" = "$selected_name" ]; then
          DEFAULT_KEY_INDEX="$index"
          break 2
        fi
      done
      if [ -f "${KEY_FILES[$index]}.pub" ]; then
        candidate_fingerprint=$(ssh-keygen -E md5 -lf "${KEY_FILES[$index]}.pub" 2>/dev/null | awk '{print $2}' | sed 's/^MD5://')
        for selected_fingerprint in "${SELECTED_DO_KEY_FINGERPRINTS[@]}"; do
          if [ "$candidate_fingerprint" = "$selected_fingerprint" ]; then
            DEFAULT_KEY_INDEX="$index"
            break 2
          fi
        done
      fi
    done
  fi

  if [ -z "$DEFAULT_KEY_INDEX" ]; then
    for preferred_name in id_ed25519 id_ecdsa id_rsa id_ed25519_sk id_ecdsa_sk; do
      for index in "${!KEY_FILES[@]}"; do
        if [ "${KEY_FILES[$index]##*/}" = "$preferred_name" ]; then
          DEFAULT_KEY_INDEX="$index"
          break 2
        fi
      done
    done
  fi
  SUGGESTED_KEY_FILE=""
  if [ -n "$DEFAULT_KEY_INDEX" ]; then
    SUGGESTED_KEY_FILE="${KEY_FILES[$DEFAULT_KEY_INDEX]}"
  fi

  read -r -p "Path to SSH private key${SUGGESTED_KEY_FILE:+ [$SUGGESTED_KEY_FILE]}: " KEY_FILE
  KEY_FILE="${KEY_FILE:-$SUGGESTED_KEY_FILE}"
  case "$KEY_FILE" in
    "~/"*) KEY_FILE="$HOME/${KEY_FILE:2}" ;;
  esac
  if [ -z "$KEY_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "Error: A valid SSH private key file path is required." >&2
    exit 1
  fi
fi
if [ -n "$KEY_FILE" ]; then
  KEY_DIR=$(cd "$(dirname "$KEY_FILE")" && pwd)
  KEY_FILE="${KEY_DIR}/${KEY_FILE##*/}"
  SSH_KEY_OPTS=(-i "$KEY_FILE" -o IdentitiesOnly=yes)
fi

# -----------------------------------------------------------------------------
# Interactive Prompts
# -----------------------------------------------------------------------------

# Prompt for RAM size if missing
if [ -z "$RAM_GB" ]; then
  read -r -p "Select RAM size in GB [4, 8, 16, 32, 64, 128, 192, 256] (default: 4): " USER_RAM_INPUT
  RAM_GB="${USER_RAM_INPUT:-4}"
fi

# Default the disk multiplier if RAM >= 16GB and the flag was missing
if [ "$RAM_GB" -ge 16 ]; then
  if [ -z "$DISK_MULT" ]; then
    DISK_MULT="1x"
    echo "Using default disk multiplier '${DISK_MULT}'. To change it, use -d/--disk <1x|3x|6x> on another run."
  fi

  # Validate and normalize disk multiplier input
  case "$DISK_MULT" in
    1|1x|1X) PREFIX="m" ;;
    3|3x|3X) PREFIX="m3" ;;
    6|6x|6X) PREFIX="m6" ;;
    *)
      echo "Error: Invalid disk size multiplier '$DISK_MULT'. Options are: 1x, 3x, 6x"
      exit 1
      ;;
  esac
elif [ -n "$DISK_MULT" ]; then
  DISK_MULT="1x"
  echo "Disk multiplier can only be 1x for RAM below 16 GB; using 1x."
fi

# Prompt for Droplet Name if missing
if [ -z "$DROPLET_NAME" ]; then
  DROPLET_NAME="$DEFAULT_NAME"
  read -r -p "Enter Droplet name (default: ${DEFAULT_NAME} - Enter accepts default): " USER_NAME_INPUT
  DROPLET_NAME="${USER_NAME_INPUT:-$DEFAULT_NAME}"
fi

# -----------------------------------------------------------------------------
# Map Configuration to DigitalOcean Size Slug
# -----------------------------------------------------------------------------
case "$RAM_GB" in
  # Basic Shared CPU (4GB - 8GB)
  4)   SIZE="s-2vcpu-4gb" ;;
  8)   SIZE="s-4vcpu-8gb" ;;
  
  # Memory-Optimized Dedicated CPU (16GB - 256GB)
  16)  SIZE="${PREFIX}-2vcpu-16gb" ;;
  32)  SIZE="${PREFIX}-4vcpu-32gb" ;;
  64)  SIZE="${PREFIX}-8vcpu-64gb" ;;
  128) SIZE="${PREFIX}-16vcpu-128gb" ;;
  192) SIZE="${PREFIX}-24vcpu-192gb" ;;
  256) SIZE="${PREFIX}-32vcpu-256gb" ;;
  *)
    echo "Error: Invalid RAM size '$RAM_GB'GB."
    echo "Supported sizes: 4, 8, 16, 32, 64, 128, 192, 256"
    exit 1
    ;;
esac

if [ "$REGION_PROVIDED" = false ]; then
REGIONS_RESPONSE=$(curl -fsS -H "Authorization: Bearer ${DO_TOKEN}" \
  "https://api.digitalocean.com/v2/regions?per_page=200") || {
  echo "Error: Could not retrieve DigitalOcean regions." >&2
  exit 1
}
if ! jq -e '.regions | type == "array"' <<< "$REGIONS_RESPONSE" >/dev/null; then
  echo "Error: DigitalOcean returned an invalid region list." >&2
  exit 1
fi

mapfile -t REGION_SLUGS < <(jq -r --arg size "$SIZE" \
  '.regions[] | select(.available == true and (.sizes | index($size))) | .slug' <<< "$REGIONS_RESPONSE")
if [ ${#REGION_SLUGS[@]} -eq 0 ]; then
  echo "Error: No available DigitalOcean regions support size ${SIZE}." >&2
  exit 1
fi

REGION_VALID=false
for region_slug in "${REGION_SLUGS[@]}"; do
  if [ "$region_slug" = "$REGION" ]; then
    REGION_VALID=true
    break
  fi
done
if [ "$REGION_VALID" != true ]; then
  echo "Default region '${REGION}' is unavailable or does not support size ${SIZE}."
  REGION="${REGION_SLUGS[0]}"
  echo "Suitable regions for ${SIZE}:"
  printf '  %s\n' "${REGION_SLUGS[@]}"
  while true; do
    read -r -p "Choose a region [${REGION} - Enter accepts default]: " REGION_CHOICE
    REGION_CHOICE="${REGION_CHOICE:-$REGION}"
    REGION_VALID=false
    for region_slug in "${REGION_SLUGS[@]}"; do
      if [ "$region_slug" = "$REGION_CHOICE" ]; then
        REGION_VALID=true
        break
      fi
    done
    if [ "$REGION_VALID" = true ]; then
      REGION="$REGION_CHOICE"
      break
    fi
    echo "Region '${REGION_CHOICE}' is not in the suitable region list. Please choose one of the regions above."
  done
fi

  echo "Using default region '${REGION}'. To change it, use -r/--region <slug> on another run."
fi

echo ""
echo "Selected configuration:"
echo "  - Memory:       ${RAM_GB} GB"
if [ "$RAM_GB" -ge 16 ]; then
echo "  - Disk Option:  ${DISK_MULT}"
fi
echo "  - Size Slug:    ${SIZE}"
echo "  - Region:       ${REGION}"
echo "  - Droplet Name: ${DROPLET_NAME}"
echo "  - Attached Keys: $SELECTED_KEY_COUNT key(s)"
echo ""

# -----------------------------------------------------------------------------
# API Call
# -----------------------------------------------------------------------------
echo "Creating Droplet '$DROPLET_NAME'..."

CREATE_PAYLOAD=$(jq -n \
  --arg name "$DROPLET_NAME" \
  --arg region "$REGION" \
  --arg size "$SIZE" \
  --arg image "$IMAGE" \
  --argjson ssh_keys "$SSH_KEYS" \
  '{name: $name, region: $region, size: $size, image: $image, ssh_keys: $ssh_keys, backups: false, ipv6: true, user_data: null}')

RESPONSE=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${DO_TOKEN}" \
  -d "$CREATE_PAYLOAD" \
  "https://api.digitalocean.com/v2/droplets")

# Check if the API returned an error
if echo "$RESPONSE" | jq -e '.id' > /dev/null 2>&1; then
  echo "Error from DigitalOcean API:"
  echo "$RESPONSE" | jq '.message'
  if [ "$REGION_PROVIDED" = true ] && jq -e '.message // "" | test("region|datacenter"; "i") and test("size|type|available|availability"; "i")' <<< "$RESPONSE" >/dev/null; then
    echo "Check availability and choose a different region with -r/--region <slug>, or rerun without that parameter to auto-configure a supported region." >&2
  fi
  exit 1
fi

# Extract Droplet Details
DROPLET_ID=$(echo "$RESPONSE" | jq -r '.droplet.id')
STATUS=$(echo "$RESPONSE" | jq -r '.droplet.status')

echo "SUCCESS: Droplet created!"
echo "Droplet ID:     $DROPLET_ID"
echo "Initial Status: $STATUS"
echo ""

# -----------------------------------------------------------------------------
# Poll until Droplet is active and IP is assigned
# -----------------------------------------------------------------------------
echo "Waiting for Droplet to boot and assign IP address..."

IP_ADDRESS=""
while [ -z "$IP_ADDRESS" ] || [ "$IP_ADDRESS" == "null" ]; do
  sleep 5
  INFO=$(curl -s -X GET \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${DO_TOKEN}" \
    "https://api.digitalocean.com/v2/droplets/${DROPLET_ID}")
  
  IP_ADDRESS=$(echo "$INFO" | jq -r '.droplet.networks.v4[] | select(.type=="public") | .ip_address' 2>/dev/null || true)
done

echo "Droplet is online!"
echo "Public IP Address: $IP_ADDRESS"
if [ -n "$KEY_FILE" ]; then
  printf 'Connect with: ssh -i %q -o IdentitiesOnly=yes root@%s\n' "$KEY_FILE" "$IP_ADDRESS"
else
  echo "Connect with: ssh root@$IP_ADDRESS"
fi

# -----------------------------------------------------------------------------
# Check for SSH accessibility
# -----------------------------------------------------------------------------
attempts=5
wait_seconds=20
ssh_succeeded=false

for attempt in $(seq 1 "$attempts"); do
  echo "Waiting for SSH on root@${IP_ADDRESS} (attempt ${attempt}/${attempts})..."
  sleep "$wait_seconds"
  if ssh "${SSH_KEY_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@${IP_ADDRESS}" "true" >/dev/null 2>&1; then
    echo "SSH is ready on ${IP_ADDRESS}."
    ssh_succeeded=true
    break
  fi
done

if [ "$ssh_succeeded" = false ]; then
  echo "Error: SSH did not become available on ${IP_ADDRESS}."
  echo "Please try again manually. Once the droplet is reachable, you can continue to configure the droplet."
  exit 1
fi
