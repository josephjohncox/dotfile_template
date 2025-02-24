#!/bin/zsh

# Paths
DOTFILES_DIR="$HOME/dev_configs"
TMP_DIR="$DOTFILES_DIR/.tmp"

# Function to manage encrypted archives with custom file operations
# Usage: manage_encrypted_archive <operation> <source_dir> <archive_name> <encrypted_archive_name> <password> <file_operation>
# - operation: --backup or --restore
# - source_dir: Directory to backup or restore
# - archive_name: Name of the archive
# - encrypted_archive_name: Name of the encrypted archive
# - password: Password for encryption/decryption
# - file_operation: Function to handle specific file operations
manage_encrypted_archive() {
  local operation="$1"
  local source_dir="$2"
  local archive_name="$3"
  local encrypted_archive_name="$4"
  local password="$5"
  local file_operation="$6"

  local temp_dir="$TMP_DIR/$archive_name"
  local archive_file="$TMP_DIR/$archive_name.tar.gz"
  local encrypted_archive_file="$DOTFILES_DIR/$encrypted_archive_name.tar.gz.gpg"

  case "$operation" in
    --backup)
      echo "Backing up $archive_name..."
      rm -rf "$temp_dir"
      mkdir -p "$temp_dir"
      $file_operation "backup" "$source_dir" "$temp_dir"
      tar -czf "$archive_file" -C "$temp_dir" .
      echo "$password" | gpg --batch --yes --passphrase-fd 0 --symmetric --cipher-algo AES256 -o "$encrypted_archive_file" "$archive_file"
      rm -f "$archive_file"
      rm -rf "$temp_dir"
      echo "✅ $archive_name backup encrypted and saved to $encrypted_archive_file."
      ;;
    --restore)
      echo "Restoring $archive_name..."
      echo "$password" | gpg --batch --yes --passphrase-fd 0 --decrypt "$encrypted_archive_file" > "$archive_file"
      mkdir -p "$source_dir"
      tar -xzf "$archive_file" -C "$source_dir"
      $file_operation "restore" "$source_dir" "$temp_dir"
      rm -f "$archive_file"
      rm -rf "$temp_dir"
      echo "✅ $archive_name restored successfully."
      ;;
    *)
      echo "Invalid operation. Use --backup or --restore."
      exit 1
      ;;
  esac
}

# These functions define specific operations for different types of files
ssh_file_operation() {
  case "$1" in
    backup)
      cp $2/* "$3/" 
      ;;
    restore)
      chmod 600 "$2"/*
      chmod 700 "$2"
      ;;
  esac
}

gpg_file_operation() {
  case "$1" in
    backup)
      gpg --export > "$2/public_keys.gpg"
      gpg --export-secret-keys > "$2/secret_keys.gpg"
      ;;
    restore)
      gpg --import "$2/public_keys.gpg"
      gpg --import "$2/secret_keys.gpg"
      ;;
  esac
}

macos_defaults_file_operation() {
  case "$1" in
    backup)
      for domain in $(defaults domains | tr ',' '\n'); do
        defaults export "$domain" "$2/$domain.plist"
      done
      ;;
    restore)
      for plist in "$2"/*.plist; do
        domain=$(basename "$plist" .plist)
        defaults import "$domain" "$plist"
      done
      ;;
  esac
}

plist_file_operation() {
  declare -a plists=(
    "com.apple.finder.plist"
    "com.apple.dock.plist"
    "com.googlecode.iterm2.plist"
    "com.apple.Terminal.plist"
    "com.microsoft.VSCode.plist"
  )
  case "$1" in
    backup)
      for plist in "${plists[@]}"; do
        cp "$HOME/Library/Preferences/$plist" "$2/"
        echo "Backed up: $plist"
      done
      ;;
    restore)
      for plist in "${plists[@]}"; do
        cp "$2/$plist" "$HOME/Library/Preferences/"
        echo "Restored: $plist"
      done
      ;;
  esac
}

# Function to manage SSH keys
# Usage: manage_ssh <operation> <password>
# - operation: --backup or --restore
# - password: GPG password for encryption/decryption
manage_ssh() {
  local GPG_PASSWORD="$2"
  manage_encrypted_archive "$1" ~/.ssh "ssh_keys" "ssh_keys" "$GPG_PASSWORD" ssh_file_operation
}

# Function to manage GPG keys
# Usage: manage_gpg <operation> <password>
# - operation: --backup or --restore
# - password: GPG password for encryption/decryption
manage_gpg() {
  local GPG_PASSWORD="$2"
  manage_encrypted_archive "$1" "$TMP_DIR/gpg_keys" "gpg_keys" "gpg_keys" "$GPG_PASSWORD" gpg_file_operation
}

# Function to manage macOS system preferences
# Usage: manage_macos_defaults <operation> <password>
# - operation: --backup or --restore
# - password: GPG password for encryption/decryption
manage_macos_defaults() {
  local GPG_PASSWORD="$2"
  manage_encrypted_archive "$1" "$TMP_DIR/macos_defaults" "macos_defaults" "macos_defaults" "$GPG_PASSWORD" macos_defaults_file_operation
}

# Function to sync application plist files
# Usage: sync_plists <operation> <password>
# - operation: --backup or --restore
# - password: GPG password for encryption/decryption
sync_plists() {
  local GPG_PASSWORD="$2"
  manage_encrypted_archive "$1" "$TMP_DIR/plists" "plists" "plists" "$GPG_PASSWORD" plist_file_operation
}

# Function to sync Cursor configs to dev_configs
sync_cursor_to() {
  SOURCE_DIR="$HOME/Library/Application Support/Cursor/User"
  DEST_DIR="$HOME/dev_configs/cursor"
  echo "Syncing local Cursor config to dev_configs..."
  mkdir -p "$DEST_DIR"
  cp "$SOURCE_DIR/settings.json" "$DEST_DIR/"
  cp "$SOURCE_DIR/keybindings.json" "$DEST_DIR/"
  cursor --list-extensions > "$DEST_DIR/extensions.txt"
  echo "✅ Sync to dev_configs completed."
}

# Function to sync Cursor configs from dev_configs to local
sync_cursor_from() {
  SOURCE_DIR="$HOME/Library/Application Support/Cursor/User"
  DEST_DIR="$HOME/dev_configs/cursor"
  echo "Syncing dev_configs back to local Cursor config..."
  cp "$DEST_DIR/settings.json" "$SOURCE_DIR/"
  cp "$DEST_DIR/keybindings.json" "$SOURCE_DIR/"
  xargs -n1 cursor --install-extension < "$DEST_DIR/extensions.txt"
  echo "✅ Sync from dev_configs completed."
}

# Function to link dotfiles using a for loop
link_dotfiles() {
  echo "Linking dotfiles from $DOTFILES_DIR..."

  declare -a dotfiles=(
    ".bash_aliases"
    ".bash_alias"
    ".zsh_aliases"
    ".zsh_alias"
    ".bashrc"
    ".bashrc.mac"
    ".bashrc.linux"
    ".bash_profile"
    ".bash_profile.mac"
    ".bash_profile.linux"
    ".eslintrc"
    ".zshrc"
    ".direnvrc"
    ".vim/*"
    ".bin/*"
    ".p10k.zsh"
    ".ideavimrc"
    ".Rprofile"
  )

  for file in "${dotfiles[@]}"; do
    ln -sf "$DOTFILES_DIR/$file" "$HOME/$file"
    echo "Linked: $file"
  done

  echo "✅ Dotfiles linked successfully."
}

# Function to manage Homebrew Brewfile
# Usage: manage_brewfile <operation>
# - operation: --backup, --restore, or --check
manage_brewfile() {
  local BREWFILE="$DOTFILES_DIR/Brewfile"
  case "$1" in
    --backup)
      echo "Backing up Homebrew packages to $BREWFILE..."
      brew bundle dump --file="$BREWFILE" --force
      echo "✅ Brewfile backup completed."
      ;;

    --restore)
      echo "Restoring Homebrew packages from $BREWFILE..."
      brew bundle --file="$BREWFILE"
      echo "✅ Brewfile restore completed."
      ;;

    --check)
      echo "Checking for missing or outdated Homebrew packages..."
      brew bundle check --file="$BREWFILE"
      ;;

    *)
      echo "Usage: $0 brewfile [--backup|--restore|--check]"
      exit 1
      ;;
  esac
}

# Function to manage Git configuration
# Usage: manage_git_config <operation>
# - operation: --backup or --restore
manage_git_config() {
  local GIT_CONFIG="$DOTFILES_DIR/gitconfig"
  case "$1" in
    --backup)
      echo "Backing up Git config..."
      cp ~/.gitconfig "$GIT_CONFIG"
      echo "✅ Git config backup completed."
      ;;
    --restore)
      echo "Restoring Git config..."
      cp "$GIT_CONFIG" ~/.gitconfig
      ln -sf "$DOTFILES_DIR/.gitignore_global" ~/.gitignore
      echo "✅ Git config restore completed."
      ;;
    *)
      echo "Usage: $0 git-config [--backup|--restore]"
      exit 1
      ;;
  esac
}

# Function to manage firewall settings
# This function enables the firewall on the system
manage_firewall() {
  echo "Managing firewall settings..."
  sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
  echo "✅ Firewall enabled."
}

# Function to manage network settings
# This function lists all network services
manage_network() {
  echo "Managing network settings..."
  networksetup -listallnetworkservices
  echo "✅ Network services listed."
}

# Function to manage Kubernetes configurations
# Usage: manage_kube_config <operation>
# - operation: --backup or --restore
manage_kube_config() {
  KUBE_CONFIG_DIR="$DOTFILES_DIR/kube"
  KUBE_CONFIG_BACKUP="$KUBE_CONFIG_DIR/config"

  case "$1" in
    --backup)
      echo "Backing up Kubernetes config..."
      mkdir -p "$KUBE_CONFIG_DIR"
      cp ~/.kube/config "$KUBE_CONFIG_BACKUP"
      echo "✅ Kubernetes config backup completed."
      ;;
    --restore)
      echo "Restoring Kubernetes config..."
      cp "$KUBE_CONFIG_BACKUP" ~/.kube/config
      echo "✅ Kubernetes config restore completed."
      ;;
    *)
      echo "Usage: $0 kube-config [--backup|--restore]"
      exit 1
      ;;
  esac
}

# Function to manage Docker configurations
# Usage: manage_docker <operation>
# - operation: --backup or --restore
manage_docker() {
  DOCKER_CONFIG_DIR="$DOTFILES_DIR/docker"
  DOCKER_CONFIG_BACKUP="$DOCKER_CONFIG_DIR/config"

  case "$1" in
    --backup)
      echo "Backing up Docker configurations..."
      mkdir -p "$DOCKER_CONFIG_DIR"
      cp -r ~/.docker "$DOCKER_CONFIG_BACKUP"
      echo "✅ Docker configurations backup completed."
      ;;
    --restore)
      echo "Restoring Docker configurations..."
      cp -r "$DOCKER_CONFIG_BACKUP" ~/.docker
      echo "✅ Docker configurations restore completed."
      ;;
    *)
      echo "Usage: $0 docker [--backup|--restore]"
      exit 1
      ;;
  esac
}

# Function to manage custom scripts
# Usage: manage_custom_scripts <operation>
# - operation: --backup or --restore
manage_custom_scripts() {
  SCRIPTS_DIR="$DOTFILES_DIR/scripts"
  SCRIPTS_BACKUP="$SCRIPTS_DIR"

  case "$1" in
    --backup)
      echo "Backing up custom scripts..."
      mkdir -p "$SCRIPTS_DIR"
      cp -r ~/bin/* "$SCRIPTS_BACKUP"
      echo "✅ Custom scripts backup completed."
      ;;
    --restore)
      echo "Restoring custom scripts..."
      cp -r "$SCRIPTS_BACKUP" ~/bin/
      echo "✅ Custom scripts restore completed."
      ;;
    *)
      echo "Usage: $0 custom-scripts [--backup|--restore]"
      exit 1
      ;;
  esac
}

# Function to store a password in the macOS Keychain
# Usage: store_password <password>
store_password() {
  local service_name="manage_configs"
  local account_name="gpg_password"
  local password="$1"

  security add-generic-password -a "$account_name" -s "$service_name" -w "$password" -U
}

# Function to retrieve a password from the macOS Keychain
# Usage: get_password
get_password() {
  local service_name="manage_configs"
  local account_name="gpg_password"

  security find-generic-password -a "$account_name" -s "$service_name" -w 2>/dev/null
}

# Function to backup all configurations
backup_all() {
  echo "Starting full backup of all configurations..."

  GPG_PASSWORD=$(get_password)
  if [ -z "$GPG_PASSWORD" ]; then
    echo "No password found in Keychain. Please enter a new password:"
    read -s GPG_PASSWORD
    store_password "$GPG_PASSWORD"
  fi

  # Use the GPG password for all encryption operations
  manage_ssh --backup "$GPG_PASSWORD"
  manage_gpg --backup "$GPG_PASSWORD"
  manage_macos_defaults --backup "$GPG_PASSWORD"
  sync_plists --backup "$GPG_PASSWORD"
  manage_brewfile --backup
  manage_git_config --backup
  manage_kube_config --backup
  # manage_docker --backup
  manage_custom_scripts --backup
  secrets_check
  echo "✅ Full backup completed."
}

# This function performs a full restore of all configurations using the specified GPG password
restore_all() {
  echo "Starting full restore of all configurations..."
  GPG_PASSWORD=$(get_password)
  if [ -z "$GPG_PASSWORD" ]; then
    echo "No password found in Keychain. Please enter a new password:"
    read -s GPG_PASSWORD
    store_password "$GPG_PASSWORD"
  fi

  manage_ssh --restore "$GPG_PASSWORD"
  manage_gpg --restore "$GPG_PASSWORD"
  manage_macos_defaults --restore "$GPG_PASSWORD"
  sync_plists --restore "$GPG_PASSWORD"
  manage_brewfile --restore
  manage_git_config --restore
  manage_kube_config --restore
  # manage_docker --restore
  manage_custom_scripts --restore
  link_dotfiles
  echo "✅ Full restore completed."
}

# Function to manage Cursor configurations
# Usage: manage_cursor <option>
# - option: --sync-to or --sync-from
manage_cursor() {
  case "$1" in
    --sync-to)
      sync_cursor_to
      ;;
    --sync-from)
      sync_cursor_from
      ;;
    *)
      echo "Usage: $0 cursor [--sync-to|--sync-from]"
      exit 1
      ;;
  esac
}

# This function commits and pushes all changes to the Git repository
sync_to_git() {
  secrets_check
  echo "Syncing configurations to Git repository..."
  git add .
  git commit -m "Backup configurations on $(date)"
  git push
  echo "✅ Configurations synced to Git."
}

# This function pulls the latest changes from the Git repository
sync_from_git() {
  echo "Syncing configurations from Git repository..."
  git pull
  echo "✅ Configurations synced from Git."
}

# This function scans the repository for sensitive information using git-secrets and gitleaks
secrets_check() {
  echo "Performing secrets check with git-secrets..."

  # Run git-secrets to scan for sensitive information
  git secrets --scan
  gitleaks git . -v
  echo "Secrets check completed."
}

# Function to add Zsh autocompletions for this script
add_zsh_completions() {
  local completion_dir="$HOME/.zsh/completions"
  local completion_file="$completion_dir/_manage_configs"

  echo "Setting up Zsh autocompletions..."

  # Create the completions directory if it doesn't exist
  mkdir -p "$completion_dir"

  # Write the completion script
  cat << 'EOF' > "$completion_file"
# Zsh completion script for manage_configs.zsh

_manage_configs() {
  local -a subcommands
  local -a options

  subcommands=(
    "cursor:Manage Cursor configurations"
    "ssh:Manage SSH keys and config"
    "gpg:Manage GPG keys"
    "macos-defaults:Manage macOS system preferences"
    "sync-plists:Sync application plist files"
    "brewfile:Manage Homebrew packages"
    "git-config:Manage Git configuration"
    "kube-config:Manage Kubernetes configuration"
    "firewall:Manage firewall settings"
    "network:Manage network settings"
    "link-dotfiles:Link dotfiles from dev_configs to home directory"
    "backup-all:Backup all configurations"
    "sync:Sync configurations to Git repository"
    "secrets-check:Check for secrets in the repository"
  )

  options=(
    "--backup:Backup configurations"
    "--restore:Restore configurations"
    "--sync-to:Sync to dev_configs"
    "--sync-from:Sync from dev_configs"
    "--check:Check for missing or outdated packages"
  )

  _arguments \
    '1: :->subcommand' \
    '2: :->option' \
    '*:: :->args'

  case $state in
    subcommand)
      _describe 'subcommand' subcommands
      ;;
    option)
      _describe 'option' options
      ;;
  esac
}

compdef _manage_configs manage_configs.zsh
EOF

  echo "✅ Zsh autocompletions set up successfully. Please restart your terminal or run 'source ~/.zshrc' to activate them."
}

# Display usage
usage() {
  echo "Usage: $0 <subcommand> [options]"
  echo ""
  echo "Subcommands:"
  echo "  cursor          Manage Cursor configurations"
  echo "                  Options: --sync-to, --sync-from"
  echo "  ssh             Manage SSH keys and config"
  echo "                  Options: --backup, --restore"
  echo "  gpg             Manage GPG keys"
  echo "                  Options: --backup, --restore"
  echo "  macos-defaults  Manage macOS system preferences"
  echo "                  Options: --backup, --restore"
  echo "  sync-plists     Sync application plist files"
  echo "                  Options: --backup, --restore"
  echo "  brewfile        Manage Homebrew packages"
  echo "                  Options: --backup, --restore, --check"
  echo "  git-config      Manage Git configuration"
  echo "                  Options: --backup, --restore"
  echo "  kube-config     Manage Kubernetes configuration"
  echo "                  Options: --backup, --restore"
  echo "  firewall        Manage firewall settings"
  echo "  network         Manage network settings"
  echo "  link-dotfiles   Link dotfiles from dev_configs to home directory"
  echo "  backup-all      Backup all configurations"
  echo "  sync            Sync configurations to Git repository"
  echo "  secrets-check   Check for secrets in the repository"
  echo "  add-completions Add Zsh autocompletions for this script"
}

# Main logic
case "$1" in
  cursor)
    manage_cursor "$2"
    ;;
  ssh)
    GPG_PASSWORD=$(get_password)
    if [ -z "$GPG_PASSWORD" ]; then
      echo "No password found in Keychain. Please enter a new password:"
      read -s GPG_PASSWORD
      store_password "$GPG_PASSWORD"
    fi
    manage_ssh "$2" "$GPG_PASSWORD"
    ;;
  gpg)
    GPG_PASSWORD=$(get_password)
    if [ -z "$GPG_PASSWORD" ]; then
      echo "No password found in Keychain. Please enter a new password:"
      read -s GPG_PASSWORD
      store_password "$GPG_PASSWORD"
    fi
    manage_gpg "$2" "$GPG_PASSWORD"
    ;;
  macos-defaults)
    GPG_PASSWORD=$(get_password)
    if [ -z "$GPG_PASSWORD" ]; then
      echo "No password found in Keychain. Please enter a new password:"
      read -s GPG_PASSWORD
      store_password "$GPG_PASSWORD"
    fi
    manage_macos_defaults "$2" "$GPG_PASSWORD"
    ;;
  sync-plists)
    GPG_PASSWORD=$(get_password)
    if [ -z "$GPG_PASSWORD" ]; then
      echo "No password found in Keychain. Please enter a new password:"
      read -s GPG_PASSWORD
      store_password "$GPG_PASSWORD"
    fi
    sync_plists "$2" "$GPG_PASSWORD"
    ;;
  brewfile)
    manage_brewfile "$2"
    ;;
  git-config)
    manage_git_config "$2"
    ;;
  kube-config)
    manage_kube_config "$2"
    ;;
  firewall)
    manage_firewall
    ;;
  network)
    manage_network
    ;;
  link-dotfiles)
    link_dotfiles
    ;;
  backup-all)
    backup_all
    ;;
  sync)
    sync_to_git
    ;;
  secrets-check)
    secrets_check
    ;;
  add-completions)
    add_zsh_completions
    ;;
  custom-scripts)
    manage_custom_scripts "$2"
    ;;
  all)
    backup_all
    sync_to_git
    ;;
  restore-all)
    sync_from_git
    restore_all
    ;;
  *)
    usage
    exit 1
    ;;
esac
