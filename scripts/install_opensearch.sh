#!/usr/bin/env bash

set -euo pipefail

DEFAULT_VERSION="2.9.0"
DEFAULT_INSTALL_DIR="$HOME/opensearch"
DEFAULT_CLUSTER_NAME="idx_$(date +%Y%m%d)"
SERVICE_NAME="opensearch"
OS_NAME="$(uname -s)"

run_as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

ensure_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  echo "Homebrew is the standard scriptable package manager for this install on macOS." >&2
  read -r -p "Homebrew is not installed. Install Homebrew now? [y/N]: " INSTALL_BREW
  INSTALL_BREW="${INSTALL_BREW:-N}"
  if [[ ! "$INSTALL_BREW" =~ ^[Yy] ]]; then
    echo "Error: Install Homebrew and required dependencies manually, then rerun this script." >&2
    return 1
  fi

  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -x /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

install_missing_command() {
  local cmd="$1"

  if command -v "$cmd" >/dev/null 2>&1; then
    return 0
  fi

  echo "Required command '$cmd' is missing. Attempting to install it..." >&2

  if [ "$OS_NAME" = "Darwin" ]; then
    ensure_homebrew && brew install "$cmd"
    return $?
  fi

  if command -v apt-get >/dev/null 2>&1; then
    local package_name="$cmd"
    [ "$cmd" = "free" ] && package_name="procps"
    run_as_root apt-get update
    run_as_root apt-get install -y "$package_name"
    return $?
  fi

  echo "Error: Automatic installation of '$cmd' currently supports macOS/Homebrew or apt-get." >&2
  return 1
}

# Parse command-line flags
usage() {
  echo "Usage: $0 [-i|--ip <ip_address>] [-k|--key <private_key>] [-n|--name <name>] [-v|--version <version>] [-d|--dir <path>] [-p|--data-dir <path>]"
  echo "  -i, --ip            Install on the specified droplet IP"
  echo "  -k, --key           SSH private key file to use for remote installation"
  echo "  -n, --name          Cluster name (default: ${DEFAULT_CLUSTER_NAME})"
  echo "  -v, --version       OpenSearch version to install"
  echo "  -d, --dir           Installation directory (default: ${DEFAULT_INSTALL_DIR})"
  echo "  -p, --data-dir      OpenSearch data directory (default: packaged data directory)"
  exit "${1:-1}"
}

SELECTED_VERSION=""
INPUT_DIR=""
INPUT_DATA_DIR=""
TARGET_IP=""
TARGET_IP_CONFIRMED=0
IDENTITY_FILE=""
CLUSTER_NAME=""
FORWARD_ARGS=()

while [[ $# -gt 0 ]]; do
  case $1 in
    -i|--ip)
      TARGET_IP="$2"
      shift 2
      ;;
    -k|--key)
      if [ $# -lt 2 ]; then
        echo "Error: $1 requires a private key file path." >&2
        exit 1
      fi
      IDENTITY_FILE="$2"
      shift 2
      ;;
    -n|--name)
      CLUSTER_NAME="$2"
      shift 2
      ;;
    -v|--version)
      SELECTED_VERSION="$2"
      FORWARD_ARGS+=("$1" "$2")
      shift 2
      ;;
    -d|--dir)
      INPUT_DIR="$2"
      FORWARD_ARGS+=("$1" "$2")
      shift 2
      ;;
    -p|--data-dir)
      INPUT_DATA_DIR="$2"
      FORWARD_ARGS+=("$1" "$2")
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

if [ -z "$CLUSTER_NAME" ]; then
  CLUSTER_NAME="$DEFAULT_CLUSTER_NAME"
  echo "Using default name '${CLUSTER_NAME}'. To change it, use -n/--name <name> on another run."
fi
FORWARD_ARGS+=(--name "$CLUSTER_NAME")

if [ -z "$TARGET_IP" ] && [ "$TARGET_IP_CONFIRMED" -eq 0 ]; then
  read -r -p "Target VM IP address (leave blank to install OpenSearch locally): " TARGET_IP
fi

if [ -z "$TARGET_IP" ] && [ "$TARGET_IP_CONFIRMED" -eq 0 ]; then
  read -r -p "Install OpenSearch on this local machine? [y/N]: " RUN_LOCAL_CHOICE
  if [[ ! "${RUN_LOCAL_CHOICE:-N}" =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
  fi
fi

if [ -n "$TARGET_IP" ]; then
  # -t gives the remote run a terminal so its prompts are shown.
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
  IDENTITY_DIR=$(cd "$(dirname "$IDENTITY_FILE")" && pwd)
  IDENTITY_FILE="${IDENTITY_DIR}/${IDENTITY_FILE##*/}"
  SSH_OPTS+=(-i "$IDENTITY_FILE" -o IdentitiesOnly=yes)

  FORWARD_ARGS+=(--target-ip-confirmed)
  REMOTE_COMMAND='cd ~/api && bash ./scripts/install_opensearch.sh'
  for argument in "${FORWARD_ARGS[@]}"; do
    printf -v REMOTE_COMMAND '%s %q' "$REMOTE_COMMAND" "$argument"
  done
  echo "Running OpenSearch installer on droplet (${TARGET_IP})..."
  ssh "${SSH_OPTS[@]}" "oaw@${TARGET_IP}" "$REMOTE_COMMAND"
  exit $?
fi

if [ "$OS_NAME" = "Darwin" ]; then
  echo "" >&2
  echo "WARNING: Building on a Linux VM is recommended." >&2

  read -r -p "Are you happy to continue? [Y/n]: " CONTINUE_CHOICE
  CONTINUE_CHOICE="${CONTINUE_CHOICE:-Y}"
  if [[ ! "$CONTINUE_CHOICE" =~ ^[Yy]$ ]]; then
    echo "Setup cancelled."
    exit 0
  fi
fi

echo "=========================================="
echo "      OpenSearch Installer Script"
echo "=========================================="

# -----------------------------------------------------------------------------
# 1. Dependency & Privileges Check
# -----------------------------------------------------------------------------
for cmd in curl tar awk; do
  if ! install_missing_command "$cmd"; then
    echo "Error: Required command '$cmd' could not be installed."
    exit 1
  fi
done

LOCAL_OPENSEARCH_RESPONSE=$(curl -s --connect-timeout 2 localhost:9200 || true)
if [ -n "$LOCAL_OPENSEARCH_RESPONSE" ]; then
  echo ""
  echo "Existing local OpenSearch response from localhost:9200:"
  echo "$LOCAL_OPENSEARCH_RESPONSE"
  echo ""
  echo "Warning: A local OpenSearch service already appears to be running."
  echo "OpenSearch installation cancelled."
  exit 0
fi

# Ensure script can execute sudo commands for service setup on Linux
if [ "$OS_NAME" != "Darwin" ] && [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
  echo "Error: This script requires passwordless sudo privileges to create and enable the systemd service."
  exit 1
fi

# Detect CPU Architecture
ARCH=$(uname -m)
case "$ARCH" in
  x86_64)
    OS_ARCH="x64"
    ;;
  aarch64|arm64)
    OS_ARCH="arm64"
    ;;
  *)
    echo "Error: Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

if [ "$OS_NAME" = "Darwin" ]; then
  ARTIFACT_OS="darwin"
else
  ARTIFACT_OS="linux"
fi

# -----------------------------------------------------------------------------
# 2. Fetch Available Versions from GitHub API (if version not specified)
# -----------------------------------------------------------------------------
if [ -z "$SELECTED_VERSION" ]; then
  read -r -p "Confirm OpenSearch version [default: ${DEFAULT_VERSION}]: " USER_VER
  SELECTED_VERSION="${USER_VER:-$DEFAULT_VERSION}"
fi

# -----------------------------------------------------------------------------
# 3. Calculate Default Heap Memory (-Xms / -Xmx)
# -----------------------------------------------------------------------------
if [ "$OS_NAME" = "Darwin" ]; then
  TOTAL_RAM_MB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 ))
else
  if ! install_missing_command free; then
    echo "Error: Required command 'free' could not be installed."
    exit 1
  fi
  TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
fi
HALF_RAM_GB=$(( TOTAL_RAM_MB / 2 / 1024 ))

if [ "$HALF_RAM_GB" -lt 1 ]; then
  HALF_RAM_GB=1
fi

if [ "$HALF_RAM_GB" -gt 31 ]; then
  DEFAULT_HEAP="31g"
else
  DEFAULT_HEAP="${HALF_RAM_GB}g"
fi

echo ""
echo "Detected System RAM: $(( TOTAL_RAM_MB / 1024 )) GB"
read -r -p "Enter JVM Heap size (-Xms/-Xmx) [default: ${DEFAULT_HEAP}]: " INPUT_HEAP
HEAP_SIZE="${INPUT_HEAP:-$DEFAULT_HEAP}"

if [[ "$HEAP_SIZE" =~ ^[0-9]+$ ]]; then
  HEAP_SIZE="${HEAP_SIZE}g"
fi

# -----------------------------------------------------------------------------
# 4. Cluster Name & Installation Directory Setup
# -----------------------------------------------------------------------------
echo ""
echo ""
INSTALL_DIR="${INPUT_DIR:-$DEFAULT_INSTALL_DIR}"
if [ -z "$INPUT_DIR" ]; then
  echo "Using default installation directory '${INSTALL_DIR}'. To change it, use -d/--dir <path> when running this script."
fi

if [ -n "$INPUT_DATA_DIR" ]; then
  DATA_DIR="$INPUT_DATA_DIR"
else
  DATA_DIR=""
  echo "Using the packaged default data directory. To set a separate directory, use -p/--data-dir <path> when running this script."
fi

case "$INSTALL_DIR" in
  "~") INSTALL_DIR="$HOME" ;;
  "~/"*) INSTALL_DIR="$HOME/${INSTALL_DIR:2}" ;;
esac
case "$DATA_DIR" in
  "~") DATA_DIR="$HOME" ;;
  "~/"*) DATA_DIR="$HOME/${DATA_DIR:2}" ;;
esac
RUN_USER=$(id -un)
RUN_GROUP=$(id -gn)

# -----------------------------------------------------------------------------
# 5. Download and Extract OpenSearch
# -----------------------------------------------------------------------------
TAR_BALL="opensearch-${SELECTED_VERSION}-${ARTIFACT_OS}-${OS_ARCH}.tar.gz"
DOWNLOAD_URL="https://artifacts.opensearch.org/releases/bundle/opensearch/${SELECTED_VERSION}/${TAR_BALL}"

echo ""
echo "Downloading OpenSearch v${SELECTED_VERSION} (${OS_ARCH})..."
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

if ! curl -SL --progress-bar "$DOWNLOAD_URL" -o "${TMP_DIR}/${TAR_BALL}"; then
  echo "Error: Failed to download OpenSearch from ${DOWNLOAD_URL}"
  exit 1
fi

echo "Extracting OpenSearch to ${INSTALL_DIR}..."
mkdir -p "$INSTALL_DIR"
tar -xzf "${TMP_DIR}/${TAR_BALL}" -C "$INSTALL_DIR" --strip-components=1

# -----------------------------------------------------------------------------
# 6. Configure OpenSearch (opensearch.yml & jvm.options)
# -----------------------------------------------------------------------------
echo ""
echo "Configuring OpenSearch settings in opensearch.yml..."

CONFIG_FILE="${INSTALL_DIR}/config/opensearch.yml"

if [ -n "$DATA_DIR" ]; then
  echo "Using OpenSearch data directory: ${DATA_DIR}"
  if [ ! -d "$DATA_DIR" ]; then
    read -r -p "Data directory '${DATA_DIR}' does not exist. Create it? [Y/n]: " CREATE_DATA_DIR
    CREATE_DATA_DIR="${CREATE_DATA_DIR:-Y}"

    if [[ ! "$CREATE_DATA_DIR" =~ ^[Yy]$ ]]; then
      echo "OpenSearch installation cancelled because the data directory was not created."
      exit 0
    fi
    mkdir -p "$DATA_DIR"
  fi
fi

cat << EOF >> "$CONFIG_FILE"

# Custom Configuration
cluster.name: ${CLUSTER_NAME}
network.host: 127.0.0.1
http.port: 9200
discovery.type: single-node
plugins.security.disabled: true
indices.query.bool.max_clause_count: 20000
cluster.routing.allocation.disk.threshold_enabled: false
node.max_local_storage_nodes: 3
bootstrap.memory_lock: true
EOF

if [ -n "$DATA_DIR" ]; then
  printf 'path.data: %s\n' "$DATA_DIR" >> "$CONFIG_FILE"
fi

echo "Configuring JVM Heap size (${HEAP_SIZE}) in jvm.options..."
JVM_OPTIONS_FILE="${INSTALL_DIR}/config/jvm.options"

if grep -q "^-Xms" "$JVM_OPTIONS_FILE"; then
  if [ "$OS_NAME" = "Darwin" ]; then
    sed -i '' "s/^-Xms.*/-Xms${HEAP_SIZE}/" "$JVM_OPTIONS_FILE"
    sed -i '' "s/^-Xmx.*/-Xmx${HEAP_SIZE}/" "$JVM_OPTIONS_FILE"
  else
    sed -i "s/^-Xms.*/-Xms${HEAP_SIZE}/" "$JVM_OPTIONS_FILE"
    sed -i "s/^-Xmx.*/-Xmx${HEAP_SIZE}/" "$JVM_OPTIONS_FILE"
  fi
else
  echo "-Xms${HEAP_SIZE}" >> "$JVM_OPTIONS_FILE"
  echo "-Xmx${HEAP_SIZE}" >> "$JVM_OPTIONS_FILE"
fi

# -----------------------------------------------------------------------------
# 7. System Optimizations (vm.max_map_count)
# -----------------------------------------------------------------------------
if [ "$OS_NAME" = "Darwin" ]; then
  echo "Skipping Linux vm.max_map_count tuning on macOS."
else
  echo "Checking system kernel settings..."
  CURRENT_MAX_MAP=$(sysctl -n vm.max_map_count 2>/dev/null || echo "0")
  if [ "$CURRENT_MAX_MAP" -lt 262144 ]; then
    echo "Setting vm.max_map_count to 262144..."
    if [ "$(id -u)" -eq 0 ]; then
      sysctl -w vm.max_map_count=262144
      echo "vm.max_map_count=262144" >> /etc/sysctl.conf
    else
      sudo sysctl -w vm.max_map_count=262144
      echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf >/dev/null
    fi
  fi
fi

# -----------------------------------------------------------------------------
# 8. Create and Enable Service
# -----------------------------------------------------------------------------
echo ""
if [ "$OS_NAME" = "Darwin" ]; then
  echo "Creating launchd service '${SERVICE_NAME}'..."
  LAUNCHD_DIR="$HOME/Library/LaunchAgents"
  SERVICE_FILE="${LAUNCHD_DIR}/org.opensearch.${SERVICE_NAME}.plist"
  mkdir -p "$LAUNCHD_DIR"

  cat > "$SERVICE_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>org.opensearch.${SERVICE_NAME}</string>
  <key>WorkingDirectory</key>
  <string>${INSTALL_DIR}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${INSTALL_DIR}/bin/opensearch</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${INSTALL_DIR}/logs/launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>${INSTALL_DIR}/logs/launchd.err.log</string>
</dict>
</plist>
EOF

  launchctl bootout "gui/$(id -u)" "$SERVICE_FILE" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$SERVICE_FILE"
  launchctl enable "gui/$(id -u)/org.opensearch.${SERVICE_NAME}"
else
  echo "Creating systemd service '${SERVICE_NAME}.service'..."

  SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

  SYSTEMD_CONTENT=$(cat << EOF
[Unit]
Description=OpenSearch Search Engine
Documentation=https://opensearch.org
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_GROUP}
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/bin/opensearch
Restart=always
RestartSec=10
LimitNOFILE=65535
LimitNPROC=4096
LimitMEMLOCK=infinity
TimeoutStopSec=0
KillSignal=SIGTERM
SendSIGKILL=no
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF
)

  if [ "$(id -u)" -eq 0 ]; then
    echo "$SYSTEMD_CONTENT" > "$SERVICE_FILE"
    systemctl daemon-reload
    systemctl enable --now "$SERVICE_NAME"
  else
    echo "$SYSTEMD_CONTENT" | sudo tee "$SERVICE_FILE" >/dev/null
    sudo systemctl daemon-reload
    sudo systemctl enable --now "$SERVICE_NAME"
  fi
fi

# -----------------------------------------------------------------------------
# 9. Summary & Verification
# -----------------------------------------------------------------------------
echo ""
echo "=========================================="
echo " SUCCESS: OpenSearch v${SELECTED_VERSION} installed!"
echo " Cluster Name: ${CLUSTER_NAME}"
echo " Heap Memory: ${HEAP_SIZE}"
echo " Service: ${SERVICE_NAME}.service"
echo " Location: ${INSTALL_DIR}"
[ -n "$DATA_DIR" ] && echo " Data Directory: ${DATA_DIR}"
echo "=========================================="
echo ""
echo "Waiting for OpenSearch to respond on http://localhost:9200..."

for i in {1..15}; do
  if curl -s http://localhost:9200 >/dev/null; then
    echo ""
    echo "OpenSearch is live and responding:"
    curl -s http://localhost:9200
    break
  fi
  sleep 2
done

echo ""
echo "Notice: OpenSearch is still starting up. Check status anytime with:"
if [ "$OS_NAME" = "Darwin" ]; then
  echo "  launchctl print gui/$(id -u)/org.opensearch.${SERVICE_NAME}"
else
  echo "  sudo systemctl status ${SERVICE_NAME}"
fi

echo ""
echo "Note, if you have a new oaworks API running on the same VM,"
echo "you must configure the server/secrets/server.json or the"
echo "worker/secrets/settings.json with an .index.url value:"
echo "http://localhost:9200"
echo ""
echo "Then rebuild the API to enable it to use this instance of OpenSearch."
echo "Whilst this could be done automatically, it is best to do manually."
echo "This ensures you have control over connecting to any index."
echo ""
echo "Also, as the purpose of these scripts is to create a dev instance"
echo "consider this a learning task for how to configure the API codebase."
