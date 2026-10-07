#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
API_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)
START_API="false"
EXPOSE_API_PORT="false"
PUBLIC_IP=""
API_PORT_EXPOSED="false"
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

ensure_macos_build_tools() {
  if xcode-select -p >/dev/null 2>&1; then
    return 0
  fi

  echo "Xcode Command Line Tools are required for native npm builds on macOS." >&2
  read -r -p "Install Xcode Command Line Tools now? [y/N]: " INSTALL_XCODE_TOOLS
  INSTALL_XCODE_TOOLS="${INSTALL_XCODE_TOOLS:-N}"
  if [[ ! "$INSTALL_XCODE_TOOLS" =~ ^[Yy] ]]; then
    echo "Error: Install Xcode Command Line Tools manually, then rerun this script." >&2
    return 1
  fi

  xcode-select --install
  echo "Finish the Xcode Command Line Tools installer, then rerun this script." >&2
  return 1
}

install_macos_package() {
  local package_name="$1"
  local command_name="${2:-$package_name}"

  if command -v "$command_name" >/dev/null 2>&1; then
    return 0
  fi

  ensure_homebrew && brew install "$package_name"
}

install_linux_packages() {
  run_as_root apt-get update -qq
  run_as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$@"
}

# Parse CLI arguments
usage() {
  echo "Usage: $0 [-i|--ip <ip_address>] [-k|--key <private_key>] [-s|--start-api] [-e|--expose-api-port]"
  echo "  -i, --ip    Install on the specified droplet IP"
  echo "  -k, --key   SSH private key file to use for remote installation"
  echo "  -s, --start-api  Start the API after building and check localhost:4000"
  echo "  -e, --expose-api-port  Allow inbound traffic on port 4000 after a successful start"
  exit 1
}

TARGET_IP=""
IDENTITY_FILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -i|--ip)
      if [ $# -lt 2 ]; then
        echo "Error: $1 requires an IP address." >&2
        usage
      fi
      TARGET_IP="$2"
      shift 2
      ;;
    -k|--key)
      if [ $# -lt 2 ]; then
        echo "Error: $1 requires a private key file path." >&2
        usage
      fi
      IDENTITY_FILE="$2"
      shift 2
      ;;
    -s|--start-api)
      START_API="true"
      shift
      ;;
    -e|--expose-api-port)
      EXPOSE_API_PORT="true"
      shift
      ;;
    --api-public-ip)
      PUBLIC_IP="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

if [ -z "$TARGET_IP" ] && [ -z "$PUBLIC_IP" ]; then
  read -r -p "Install on this local machine? [Y/n]: " RUN_LOCAL_CHOICE
  if [[ ! "${RUN_LOCAL_CHOICE:-Y}" =~ ^[Yy]$ ]]; then
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
  SSH_OPTS+=(-i "$IDENTITY_FILE" -o IdentitiesOnly=yes)

  # The remote run skips its local-install prompt when --api-public-ip is set.
  PUBLIC_IP="${PUBLIC_IP:-$TARGET_IP}"

  REMOTE_COMMAND='cd ~/api && bash ./scripts/install_oaworks_api.sh'
  if [ "$START_API" = "true" ]; then
    printf -v REMOTE_COMMAND '%s %q' "$REMOTE_COMMAND" --start-api
  fi
  if [ "$EXPOSE_API_PORT" = "true" ]; then
    printf -v REMOTE_COMMAND '%s %q' "$REMOTE_COMMAND" --expose-api-port
  fi
  if [ -n "$PUBLIC_IP" ]; then
    printf -v REMOTE_COMMAND '%s %q %q' "$REMOTE_COMMAND" --api-public-ip "$PUBLIC_IP"
  fi

  echo "Running OA.Works API installer on droplet (${TARGET_IP})..."
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
echo "    OA.Works API Installer Script"
echo "=========================================="

# -----------------------------------------------------------------------------
# 1. Privileges Check
# -----------------------------------------------------------------------------
if [ "$OS_NAME" != "Darwin" ] && [ "$(id -u)" -ne 0 ] && ! sudo -n true 2>/dev/null; then
  echo "Error: This script requires passwordless sudo privileges to install system packages."
  exit 1
fi

# -----------------------------------------------------------------------------
# 2. Install System Dependencies & Node.js
# -----------------------------------------------------------------------------
echo ""
if [ "$OS_NAME" = "Darwin" ]; then
  echo "Installing macOS document tools and utilities..."
  ensure_macos_build_tools
  install_macos_package poppler pdftotext
  install_macos_package antiword
  install_macos_package unoconv
  install_macos_package unzip
  install_macos_package pdftk-java pdftk
else
  echo "Installing Linux document tools and utilities..."
  install_linux_packages curl build-essential pdftk poppler-utils antiword unoconv unzip
fi

# Check and install Node.js (LTS v20) if node or npm are missing
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "Node.js/npm not detected. Installing Node.js LTS (v20.x)..."
  if [ "$OS_NAME" = "Darwin" ]; then
    ensure_homebrew
    brew install node@20
    NODE20_PREFIX="$(brew --prefix node@20)"
    export PATH="${NODE20_PREFIX}/bin:$PATH"
  else
    if [ "$(id -u)" -eq 0 ]; then
      curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
      apt-get install -y -qq nodejs
    else
      curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
      sudo apt-get install -y -qq nodejs
    fi
  fi
else
  echo "Node.js $(node -v) and npm $(npm -v) are already installed."
fi

# -----------------------------------------------------------------------------
# 3. Build API Application
# -----------------------------------------------------------------------------
echo ""
echo "Building the API in ${API_DIR}..."
cd "$API_DIR"
API_BRANCH=$(git branch --show-current 2>/dev/null || true)

echo "Installing Node.js dependencies (npm install)..."
npm install

echo "Building the API application... (npm run build -> coffee construct.coffee)"
npm run build

API_SUCCEEDED=true
if [ "$START_API" = "true" ]; then
  echo "Starting API with 'npm run start'..."
  nohup npm run start &

  echo "Waiting 10 seconds for the API to start..."
  sleep 10
  if curl --silent --show-error --output /dev/null --connect-timeout 3 --max-time 5 http://localhost:4000; then
    echo "SUCCESS: API is responding at http://localhost:4000."
    if [ "$EXPOSE_API_PORT" = "true" ]; then
      if [ "$OS_NAME" = "Darwin" ]; then
        echo "UFW is not available on macOS; port 4000 was not opened."
      elif ! command -v ufw >/dev/null 2>&1; then
        echo "ERROR: UFW is not installed; cannot allow inbound traffic on port 4000." >&2
        exit 1
      elif run_as_root ufw allow in 4000/tcp; then
        echo "SUCCESS: UFW allows inbound TCP traffic on port 4000."
        API_PORT_EXPOSED="true"
      else
        echo "ERROR: Could not configure UFW to allow inbound TCP traffic on port 4000." >&2
        exit 1
      fi
    fi
  else
    echo "ERROR: API did not respond at http://localhost:4000 after 10 seconds."
    API_SUCCEEDED=false
  fi
fi

# -----------------------------------------------------------------------------
# 4. Verification Summary
# -----------------------------------------------------------------------------
echo ""
echo "=========================================="
echo " SUCCESS: OA.Works API setup complete!"
echo " Location:     ${API_DIR}"
[ -n "$API_BRANCH" ] && echo " Branch:       ${API_BRANCH}"
echo " Node Version: $(node -v)"
echo " NPM Version:  $(npm -v)"
if [ "$START_API" = "true" ] && [ "$API_SUCCEEDED" = "true" ]; then
  echo " API Process:  Running with npm run start"
  echo " API URL:      http://localhost:4000"
  if [ "$API_PORT_EXPOSED" = "true" ] && [ -n "$PUBLIC_IP" ]; then
    echo " Public API URL: http://${PUBLIC_IP}:4000"
  fi
else
  echo " Manual start can be tried with:"
  printf 'cd %q && node server/dist/server.min.js\n' "${API_DIR}"
fi
echo ""
#echo " Further configuration should be done using the oa.works api_config repo."
#echo " This includes installing and configuring PM2 for reliable API process management."
#echo " It (will) also provide options for configuring releaseable API deployments."
echo "=========================================="
echo ""
