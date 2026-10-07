#!/usr/bin/env bash

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration & Defaults
# -----------------------------------------------------------------------------
DEFAULT_USER="oaw"
TARGET_TZ="Europe/London"
TARGET_IP=""
SSH_USER=""
IDENTITY_FILE=""
QUIET_MODE="false"
LOCAL_MODE="false"

# Package payload
USEFUL_PACKAGES=(
  jq
  nginx
  git
  1password-cli
  certbot
)

# Parse optional command-line flags
usage() {
  echo "Usage: $0 [-i|--ip <ip_address>] [-u|--user <username>] [-k|--key <private_key>]"
  echo "  -i, --ip     Target Droplet IP address"
  echo "  -u, --user   Target username to create (default: ${DEFAULT_USER})"
  echo "  -k, --key    SSH private key file to use for remote connection to the provided IP"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -i|--ip)
      TARGET_IP="$2"
      shift 2
      ;;
    -u|--user)
      SSH_USER="$2"
      shift 2
      ;;
    -k|--key)
      IDENTITY_FILE="$2"
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

# -----------------------------------------------------------------------------
# Step 1: Resolve Target Machine
# -----------------------------------------------------------------------------
if [ -z "$TARGET_IP" ]; then
  read -r -p "Target VM IP address (leave blank to configure locally): " TARGET_IP
fi

if [ -z "$TARGET_IP" ]; then
  if [ "$(uname -s)" = "Darwin" ]; then
    echo "Error: No target IP was provided, and this script is intended to configure a Linux machine. It will not run locally on macOS."
    exit 1
  fi

  read -r -p "Configure this Linux machine locally? [y/N]: " LOCAL_CHOICE
  LOCAL_CHOICE="${LOCAL_CHOICE:-N}"
  if [[ "$LOCAL_CHOICE" =~ ^[Yy]$ ]]; then
    LOCAL_MODE="true"
  else
    echo "Error: Target IP is required unless you confirm local Linux configuration. Exiting."
    exit 1
  fi
fi

# -----------------------------------------------------------------------------
# Step 2: Prompt for Desired Username
# -----------------------------------------------------------------------------
if [ -z "$SSH_USER" ]; then
  echo "Configuring for default username: ${DEFAULT_USER}"
  SSH_USER="$DEFAULT_USER"
fi

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 -o BatchMode=yes)
if [ "$LOCAL_MODE" != "true" ]; then
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
fi

run_target_check() {
  local command="$1"

  if [ "$LOCAL_MODE" = "true" ]; then
    if [ "$(id -u)" -eq 0 ]; then
      bash -c "$command"
    else
      sudo bash -c "$command"
    fi
  else
    ssh "${SSH_OPTS[@]}" "$REMOTE_LOGIN" "${REMOTE_SUDO}bash -c $(printf '%q' "$command")"
  fi
}

# -----------------------------------------------------------------------------
# Step 3: Test SSH Access as Desired User
# -----------------------------------------------------------------------------
if [ "$LOCAL_MODE" = "true" ]; then
  echo ""
  echo "Configuring this Linux machine locally."
  if [ "$(id -u)" -ne 0 ] && ! sudo -v 2>/dev/null; then
    echo "Error: Local configuration requires sudo privileges."
    exit 1
  fi
else
  echo ""
  echo "Attempting SSH connection as '${SSH_USER}' to ${TARGET_IP}..."

  REMOTE_LOGIN=""
  REMOTE_SUDO=""
  if ssh "${SSH_OPTS[@]}" "${SSH_USER}@${TARGET_IP}" "sudo -n true" 2>/dev/null; then
    echo "User '${SSH_USER}' already exists with SSH and passwordless sudo access; continuing configuration as that user."
    REMOTE_LOGIN="${SSH_USER}@${TARGET_IP}"
    REMOTE_SUDO="sudo -n "
  else
    echo "Notice: Could not use '${SSH_USER}' with sudo. Testing fallback connection as 'root'..."

    if ! ssh "${SSH_OPTS[@]}" "root@${TARGET_IP}" "echo 'Root access verified.'" 2>/dev/null; then
      echo "Error: Unable to connect via SSH as 'root' or '${SSH_USER}' to ${TARGET_IP}."
      echo "Please check that:"
      echo "  1. The server has finished booting."
      echo "  2. Your SSH key is properly loaded in your local agent (e.g., ssh-add)."
      echo "  3. The IP address is correct."
      exit 1
    fi

    echo "Root connection verified."
    REMOTE_LOGIN="root@${TARGET_IP}"
  fi
fi

# -----------------------------------------------------------------------------
# Step 5: Post-Provisioning Prompts or Auto-Defaults (-q)
# -----------------------------------------------------------------------------

# Check 1: Root SSH access choice
ROOT_LOGIN_STATUS=$(run_target_check "sshd -T 2>/dev/null | grep -i '^permitrootlogin ' | awk '{print \$2}' || echo 'yes'")

DISABLE_ROOT_CHOICE="N"
if [ "$ROOT_LOGIN_STATUS" != "no" ]; then
  echo ""
  read -p "Do you want to disable root SSH access? [Y/n]: " DISABLE_ROOT_CHOICE
  DISABLE_ROOT_CHOICE="${DISABLE_ROOT_CHOICE:-Y}"
else
  echo "Notice: Root SSH access is already disabled on this server."
fi

# Check 2: Password Authentication setting on target host
PASSWORD_AUTH_STATUS=$(run_target_check "sshd -T 2>/dev/null | grep -i '^passwordauthentication ' | awk '{print \$2}' || echo 'yes'")

DISABLE_PASSWORD_CHOICE="N"
if [ "$PASSWORD_AUTH_STATUS" = "yes" ]; then
  echo ""
  read -p "Password authentication is currently ENABLED. Would you like to disable it? [Y/n]: " PASS_CHOICE_INPUT
  PASS_CHOICE_INPUT="${PASS_CHOICE_INPUT:-Y}"
  if [[ "$PASS_CHOICE_INPUT" =~ ^[Yy]$ ]]; then
    DISABLE_PASSWORD_CHOICE="Y"
  fi
else
  echo "Notice: SSH Password authentication is already disabled on this server."
fi

# Check 3: UFW status on target host
UFW_STATUS=$(run_target_check "command -v ufw >/dev/null 2>&1 && ufw status | grep -i 'status: active' >/dev/null 2>&1 && echo 'active' || echo 'inactive'")

SETUP_UFW_CHOICE="N"
if [ "$UFW_STATUS" = "inactive" ]; then
  echo ""
  echo "UFW Firewall is not active."
  read -p "Would you like to configure UFW (default deny, allow 22, 80, 443)? [Y/n]: " UFW_CHOICE_INPUT
  UFW_CHOICE_INPUT="${UFW_CHOICE_INPUT:-Y}"
  if [[ "$UFW_CHOICE_INPUT" =~ ^[Yy]$ ]]; then
    SETUP_UFW_CHOICE="Y"
  fi
else
  echo "Notice: UFW Firewall is already installed and active."
fi

# Check 4: Timezone setting on target host
CURRENT_TZ=$(run_target_check "timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo 'UTC'")

SET_TZ_CHOICE="N"
if [ "$CURRENT_TZ" != "$TARGET_TZ" ]; then
  echo ""
  read -p "Current timezone is '$CURRENT_TZ'. Set timezone to '$TARGET_TZ'? [Y/n]: " TZ_CHOICE_INPUT
  TZ_CHOICE_INPUT="${TZ_CHOICE_INPUT:-Y}"
  if [[ "$TZ_CHOICE_INPUT" =~ ^[Yy]$ ]]; then
    SET_TZ_CHOICE="Y"
  fi
else
  echo "Notice: Timezone is already set to '$TARGET_TZ'."
fi

# Check 5: Unattended Upgrades setting on target host
AUTO_UPGRADES_STATUS=$(run_target_check "[ -f /etc/apt/apt.conf.d/20auto-upgrades ] && grep -q 'APT::Periodic::Unattended-Upgrade \"1\"' /etc/apt/apt.conf.d/20auto-upgrades && echo 'enabled' || echo 'disabled'")

SETUP_UNATTENDED_CHOICE="N"
if [ "$AUTO_UPGRADES_STATUS" = "disabled" ]; then
  echo ""
  read -p "Unattended automatic security upgrades are disabled. Enable them now? [Y/n]: " UNATTENDED_INPUT
  UNATTENDED_INPUT="${UNATTENDED_INPUT:-Y}"
  if [[ "$UNATTENDED_INPUT" =~ ^[Yy]$ ]]; then
    SETUP_UNATTENDED_CHOICE="Y"
  fi
else
  echo "Notice: Unattended automatic security upgrades are already enabled."
fi

# Check 6: Check if standard packages are installed
PACKAGES_STATUS=$(run_target_check "for package in ${USEFUL_PACKAGES[*]}; do dpkg-query -W -f='\${Status}' \"\$package\" 2>/dev/null | grep -qx 'install ok installed' || { echo missing; exit 0; }; done; command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1 && command -v pm2 >/dev/null 2>&1 && echo installed || echo missing")

INSTALL_PACKAGES_CHOICE="N"
if [ "$PACKAGES_STATUS" = "missing" ]; then
  echo ""
  echo "Useful packages to install: ${USEFUL_PACKAGES[*]}, Node.js 20, PM2"
  read -p "Would you like to install these baseline packages? [Y/n]: " PKG_CHOICE_INPUT
  PKG_CHOICE_INPUT="${PKG_CHOICE_INPUT:-Y}"
  if [[ "$PKG_CHOICE_INPUT" =~ ^[Yy]$ ]]; then
    INSTALL_PACKAGES_CHOICE="Y"
  fi
else
  echo "Notice: Core development and utility packages are already installed."
fi

# Convert choices to flags for remote script
DISABLE_ROOT_FLAG="false"
if [[ "$DISABLE_ROOT_CHOICE" =~ ^[Yy]$ ]]; then
  DISABLE_ROOT_FLAG="true"
fi

DISABLE_PASSWORD_FLAG="false"
if [[ "$DISABLE_PASSWORD_CHOICE" =~ ^[Yy]$ ]]; then
  DISABLE_PASSWORD_FLAG="true"
fi

SETUP_UFW_FLAG="false"
if [[ "$SETUP_UFW_CHOICE" =~ ^[Yy]$ ]]; then
  SETUP_UFW_FLAG="true"
fi

SET_TZ_FLAG="false"
if [[ "$SET_TZ_CHOICE" =~ ^[Yy]$ ]]; then
  SET_TZ_FLAG="true"
fi

SETUP_UNATTENDED_FLAG="false"
if [[ "$SETUP_UNATTENDED_CHOICE" =~ ^[Yy]$ ]]; then
  SETUP_UNATTENDED_FLAG="true"
fi

INSTALL_PACKAGES_FLAG="false"
if [[ "$INSTALL_PACKAGES_CHOICE" =~ ^[Yy]$ ]]; then
  INSTALL_PACKAGES_FLAG="true"
fi

# -----------------------------------------------------------------------------
# Step 6: Provision User and Apply Hardening / Configuration
# -----------------------------------------------------------------------------
echo ""
if [ "$LOCAL_MODE" = "true" ]; then
  echo "Configuring local server..."
else
  echo "Configuring remote server..."
fi

REMOTE_SCRIPT=$(cat << 'EOF'
set -euo pipefail

TARGET_USER="$1"
DISABLE_ROOT="$2"
DISABLE_PASSWORD="$3"
SETUP_UFW="$4"
SET_TZ="$5"
TARGET_TZ="$6"
SETUP_UNATTENDED="$7"
INSTALL_PACKAGES="$8"
PACKAGES_LIST="$9"

# Create user if it doesn't already exist
if id "$TARGET_USER" &>/dev/null; then
  echo "User '$TARGET_USER' already exists on remote machine."
else
  echo "Creating user '$TARGET_USER'..."
  useradd -m -s /bin/bash "$TARGET_USER"
  echo "User '$TARGET_USER' created."
fi

# Add user to sudo group
SUDOERS_FILE="/etc/sudoers.d/90-${TARGET_USER}-init"
SUDOERS_RULE="$TARGET_USER ALL=(ALL) NOPASSWD:ALL"
if id -nG "$TARGET_USER" | grep -qw sudo && [ -f "$SUDOERS_FILE" ] && grep -qxF "$SUDOERS_RULE" "$SUDOERS_FILE"; then
  echo "User '$TARGET_USER' already has passwordless sudo access."
else
  echo "Granting passwordless sudo access..."
  usermod -aG sudo "$TARGET_USER"
  echo "$SUDOERS_RULE" > "$SUDOERS_FILE"
  chmod 0440 "$SUDOERS_FILE"
fi

# Add root's authorized keys to the target user without overwriting existing keys
if [ -s /root/.ssh/authorized_keys ]; then
  echo "Adding root's authorized_keys to '$TARGET_USER'..."
  mkdir -p "/home/${TARGET_USER}/.ssh"
  touch "/home/${TARGET_USER}/.ssh/authorized_keys"
  while IFS= read -r key_line; do
    [ -n "$key_line" ] || continue
    grep -qxF "$key_line" "/home/${TARGET_USER}/.ssh/authorized_keys" || echo "$key_line" >> "/home/${TARGET_USER}/.ssh/authorized_keys"
  done < /root/.ssh/authorized_keys
  chown -R "${TARGET_USER}:${TARGET_USER}" "/home/${TARGET_USER}/.ssh"
  chmod 700 "/home/${TARGET_USER}/.ssh"
  chmod 600 "/home/${TARGET_USER}/.ssh/authorized_keys"
else
  echo "Notice: /root/.ssh/authorized_keys is empty or missing; leaving '$TARGET_USER' keys unchanged."
fi

# Clone the public API repo into the target user's home
API_CLONE_DIR="/home/${TARGET_USER}/api"
if [ -d "${API_CLONE_DIR}/.git" ]; then
  echo "API repository already exists at '${API_CLONE_DIR}'; skipping clone."
else
  if ! command -v git >/dev/null 2>&1; then
    echo "Installing git..."
    DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git
  fi
  echo "Cloning https://github.com/oaworks/api.git into '${API_CLONE_DIR}'..."
  sudo -u "$TARGET_USER" git clone https://github.com/oaworks/api.git "$API_CLONE_DIR"
  # The other setup scripts expect the develop branch.
  if sudo -u "$TARGET_USER" git -C "$API_CLONE_DIR" show-ref --verify --quiet refs/remotes/origin/develop; then
    sudo -u "$TARGET_USER" git -C "$API_CLONE_DIR" checkout --quiet develop
    echo "Checked out the develop branch."
  fi
fi

# Apply custom SSH drop-in configuration overrides
SSHD_DROPIN="/etc/ssh/sshd_config.d/99-hardened.conf"
mkdir -p /etc/ssh/sshd_config.d
touch "$SSHD_DROPIN"

if [ "$DISABLE_ROOT" = "true" ]; then
  echo "Disabling root SSH access..."
  if [ -f /root/.ssh/authorized_keys ]; then
    > /root/.ssh/authorized_keys
    echo "Cleared /root/.ssh/authorized_keys file."
  fi
  grep -qx "PermitRootLogin no" "$SSHD_DROPIN" || echo "PermitRootLogin no" >> "$SSHD_DROPIN"
fi

if [ "$DISABLE_PASSWORD" = "true" ]; then
  echo "Disabling SSH password authentication..."
  grep -qx "PasswordAuthentication no" "$SSHD_DROPIN" || echo "PasswordAuthentication no" >> "$SSHD_DROPIN"
fi

# Reload SSH service if configuration changed
if [ "$DISABLE_ROOT" = "true" ] || [ "$DISABLE_PASSWORD" = "true" ]; then
  echo "Reloading SSH daemon configuration..."
  if systemctl is-active --quiet ssh; then
    systemctl reload ssh
  elif systemctl is-active --quiet sshd; then
    systemctl reload sshd
  fi
fi

# Install and configure UFW if requested
if [ "$SETUP_UFW" = "true" ]; then
  if ! command -v ufw >/dev/null 2>&1; then
    echo "Installing ufw..."
    DEBIAN_FRONTEND=noninteractive apt-get update -qq && apt-get install -y -qq ufw
  fi

  echo "Configuring UFW firewall rules..."
  ufw --force reset >/dev/null
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 22/tcp comment 'SSH'
  ufw allow 80/tcp comment 'HTTP'
  ufw allow 443/tcp comment 'HTTPS'
  ufw --force enable
  echo "UFW enabled with ports 22, 80, and 443 open."
fi

# Set System Timezone if requested
if [ "$SET_TZ" = "true" ]; then
  echo "Setting system timezone to '$TARGET_TZ'..."
  timedatectl set-timezone "$TARGET_TZ"
  echo "Timezone successfully set to $(timedatectl show --property=Timezone --value)."
fi

# Enable Unattended Upgrades if requested
if [ "$SETUP_UNATTENDED" = "true" ]; then
  echo "Configuring unattended security upgrades..."
  DEBIAN_FRONTEND=noninteractive apt-get update -qq && apt-get install -y -qq unattended-upgrades

  cat << 'APTCONF' > /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APTCONF

  systemctl restart unattended-upgrades
  echo "Unattended security upgrades enabled successfully."
fi

# Install Requested Base Packages
if [ "$INSTALL_PACKAGES" = "true" ]; then
  if ! command -v op >/dev/null 2>&1; then
    echo "Adding 1Password CLI apt repository..."
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl gnupg ca-certificates
    curl -sS https://downloads.1password.com/linux/keys/1password.asc \
      | gpg --dearmor --yes --output /usr/share/keyrings/1password-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" \
      > /etc/apt/sources.list.d/1password.list
    mkdir -p /etc/debsig/policies/AC2D62742012EA22/ /usr/share/debsig/keyrings/AC2D62742012EA22
    curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol \
      > /etc/debsig/policies/AC2D62742012EA22/1password.pol
    curl -sS https://downloads.1password.com/linux/keys/1password.asc \
      | gpg --dearmor --yes --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg
  fi

  echo "Updating APT package lists and installing baseline packages..."
  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $PACKAGES_LIST
  if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
    echo "Installing Node.js LTS (v20.x)..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nodejs
  fi

  if ! command -v pm2 >/dev/null 2>&1; then
    echo "Installing PM2 globally with npm..."
    npm install -g pm2
  fi

  echo "Baseline packages, Node.js, and PM2 installed successfully."
fi

echo "Provisioning complete."
EOF
)

# Execute provisioning script on target machine
if [ "$LOCAL_MODE" = "true" ]; then
  if [ "$(id -u)" -eq 0 ]; then
    bash -s -- "$SSH_USER" "$DISABLE_ROOT_FLAG" "$DISABLE_PASSWORD_FLAG" "$SETUP_UFW_FLAG" "$SET_TZ_FLAG" "$TARGET_TZ" "$SETUP_UNATTENDED_FLAG" "$INSTALL_PACKAGES_FLAG" "${USEFUL_PACKAGES[*]}" <<< "$REMOTE_SCRIPT"
  else
    sudo bash -s -- "$SSH_USER" "$DISABLE_ROOT_FLAG" "$DISABLE_PASSWORD_FLAG" "$SETUP_UFW_FLAG" "$SET_TZ_FLAG" "$TARGET_TZ" "$SETUP_UNATTENDED_FLAG" "$INSTALL_PACKAGES_FLAG" "${USEFUL_PACKAGES[*]}" <<< "$REMOTE_SCRIPT"
  fi
else
  printf -v REMOTE_COMMAND '%sbash -s -- %q %q %q %q %q %q %q %q %q' "$REMOTE_SUDO" "$SSH_USER" "$DISABLE_ROOT_FLAG" "$DISABLE_PASSWORD_FLAG" "$SETUP_UFW_FLAG" "$SET_TZ_FLAG" "$TARGET_TZ" "$SETUP_UNATTENDED_FLAG" "$INSTALL_PACKAGES_FLAG" "${USEFUL_PACKAGES[*]}"
  ssh "${SSH_OPTS[@]}" "$REMOTE_LOGIN" "$REMOTE_COMMAND" <<< "$REMOTE_SCRIPT"
fi

# -----------------------------------------------------------------------------
# Step 7: Validate New User Access
# -----------------------------------------------------------------------------
echo ""
echo "Verifying new user access for '${SSH_USER}'..."

if [ "$LOCAL_MODE" = "true" ]; then
  if id "$SSH_USER" >/dev/null 2>&1 && sudo -u "$SSH_USER" sudo -n whoami >/dev/null 2>&1; then
    echo ""
    echo "SUCCESS: Local setup verified for user '${SSH_USER}'!"
  else
    echo "Warning: Provisioning completed, but local verification for '${SSH_USER}' failed."
  fi
elif ssh "${SSH_OPTS[@]}" "${SSH_USER}@${TARGET_IP}" "sudo whoami" 2>/dev/null; then
  echo ""
  echo "SUCCESS: Remote setup verified!"
  echo "You can now connect to your server using:"
  if [ -n "$IDENTITY_FILE" ]; then
    printf '  ssh -i %q -o IdentitiesOnly=yes %s@%s\n' "$IDENTITY_FILE" "$SSH_USER" "$TARGET_IP"
  else
    echo "  ssh ${SSH_USER}@${TARGET_IP}"
  fi
else
  echo "Warning: Provisioning completed, but SSH verification as '${SSH_USER}' failed."
fi
