#!/usr/bin/env bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$DOTFILES/backup"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

NVIM_SRC="$DOTFILES/nvim"
TMUX_SRC="$DOTFILES/tmux"
GHOSTTY_SRC="$DOTFILES/ghostty"
P10K_SRC="$DOTFILES/zsh/p10k.zsh"
ZSHRC_SRC="$DOTFILES/zsh/zshrc"

NVIM_LINK="$CONFIG_HOME/nvim"
TMUX_LINK="$CONFIG_HOME/tmux"
GHOSTTY_LINK="$CONFIG_HOME/ghostty"
P10K_LINK="$HOME/.p10k.zsh"
ZSHRC_FILE="$HOME/.zshrc"

DRY_RUN=0

# --- helpers ---

run_cmd() {
  if (( DRY_RUN )); then
    echo "[dry-run] $*"
  else
    "$@"
  fi
}

parse_args() {
  if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
  elif [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: $0 [--dry-run]"
    exit 0
  elif [[ -n "${1:-}" ]]; then
    echo "Unknown option: $1"
    echo "Usage: $0 [--dry-run]"
    exit 1
  fi
}

detect_os() {
  if [[ ! "$OSTYPE" == "linux-gnu"* && ! "$OSTYPE" == "darwin"* ]]; then
    echo "Operating System Not supported"
    exit 1
  fi

  if command -v apt-get &>/dev/null; then
    PKG_MGR="apt-get"
    UPDATE_CMD="sudo $PKG_MGR update"
    INSTALL_CMD="sudo $PKG_MGR install -y"
  elif command -v dnf &>/dev/null; then
    PKG_MGR="dnf"
    UPDATE_CMD=""
    INSTALL_CMD="sudo $PKG_MGR install -y"
  elif command -v brew &>/dev/null; then
    PKG_MGR="brew"
    UPDATE_CMD=""
    INSTALL_CMD="$PKG_MGR install"
  else
    echo "Unknown package manager. Please make sure you have either apt, dnf or homebrew installed"
    exit 1
  fi

  echo "Using package manager: $PKG_MGR"
  if (( DRY_RUN )); then
    echo "Dry run: no packages will be installed"
  fi
}

# Install package $1 if binary $2 is missing. Binary defaults to the package name.
install_deps() {
  local pkg="$1"
  local bin="${2:-$1}"

  if command -v "$bin" >/dev/null 2>&1; then
    echo "$bin already installed"
  else
    echo "Installing $pkg..."
    # shellcheck disable=SC2086
    run_cmd $INSTALL_CMD "$pkg"
  fi
}

install_common_deps() {
  install_deps zsh
  install_deps neovim nvim
  install_deps tmux
  install_deps curl
  install_deps fzf
  install_deps ripgrep rg
  install_deps cmake
  install_deps unzip
}

install_packages() {
  echo "Installing required dependencies..."

  case "$PKG_MGR" in
    apt-get)
      # shellcheck disable=SC2086
      run_cmd $UPDATE_CMD
      install_common_deps
      install_deps build-essential gcc
      install_deps nodejs node
      install_deps npm
      ;;
    dnf)
      install_common_deps
      install_deps gcc
      install_deps make
      install_deps nodejs node
      install_deps npm
      ;;
    brew)
      echo "Warning: Homebrew support is experimental / untested"
      install_common_deps
      install_deps node
      ;;
  esac
}

backup_if_needed() {
  local src="$1"
  local dest="$2"

  if [[ ! -e "$src" && ! -L "$src" ]]; then
    echo "No existing config at $src (skip)"
    return 0
  fi

  if [[ -L "$src" ]]; then
    local target
    target="$(readlink "$src")"
    case "$target" in
      "$DOTFILES"/*)
        echo "$src already linked to this repo (skip backup)"
        return 0
        ;;
    esac
  fi

  ensure_backup_root
  echo "Backing up $src -> $dest"
  run_cmd mv "$src" "$dest"
}

link_config() {
  local src="$1"
  local dest="$2"

  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    echo "$dest already linked (skip)"
    return 0
  fi

  if [[ -e "$dest" || -L "$dest" ]]; then
    if (( DRY_RUN )); then
      echo "[dry-run] ln -s $src $dest"
      return 0
    fi
    echo "Error: $dest still exists after backup; refusing to overwrite"
    exit 1
  fi

  echo "Linking $dest -> $src"
  run_cmd ln -s "$src" "$dest"
}

confirm() {
  local reply
  read -r -p "$1 [Y/n] " reply
  case "$reply" in
    ""|y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# Prepare backup/ once (prompt to overwrite if it already exists).
ensure_backup_root() {
  if [[ -n "${BACKUP_READY:-}" ]]; then
    return 0
  fi

  if [[ -e "$BACKUP_ROOT" ]]; then
    local reply
    read -r -p "Backup already exists at $BACKUP_ROOT. Overwrite? [y/N] " reply
    case "$reply" in
      y|Y|yes|YES) ;;
      *)
        echo "Aborting."
        exit 1
        ;;
    esac
    echo "Removing existing backup..."
    run_cmd rm -rf "$BACKUP_ROOT"
  fi

  run_cmd mkdir -p "$BACKUP_ROOT"
  BACKUP_READY=1
}

wire_zshrc() {
  local line="source \"$ZSHRC_SRC\""

  echo "Wiring ~/.zshrc -> $ZSHRC_SRC"

  if [[ ! -f "$ZSHRC_FILE" ]]; then
    echo "Creating $ZSHRC_FILE"
    if (( DRY_RUN )); then
      echo "[dry-run] write: $line"
    else
      echo "$line" > "$ZSHRC_FILE"
    fi
  elif grep -Fq "$ZSHRC_SRC" "$ZSHRC_FILE"; then
    echo "$ZSHRC_FILE already sources dotfiles (skip)"
  else
    echo "Appending source line to $ZSHRC_FILE"
    if (( DRY_RUN )); then
      echo "[dry-run] append: $line"
    else
      echo "$line" >> "$ZSHRC_FILE"
    fi
  fi
}

SETUP_NVIM=0
SETUP_TMUX=0
SETUP_GHOSTTY=0
SETUP_ZSH=0

setup_nvim() {
  echo
  if ! confirm "Set up neovim config?"; then
    echo "Skipping neovim"
    return 0
  fi
  SETUP_NVIM=1
  run_cmd mkdir -p "$CONFIG_HOME"
  backup_if_needed "$NVIM_LINK" "$BACKUP_ROOT/nvim"
  link_config "$NVIM_SRC" "$NVIM_LINK"
}

setup_tmux() {
  echo
  if ! confirm "Set up tmux config?"; then
    echo "Skipping tmux"
    return 0
  fi
  SETUP_TMUX=1
  run_cmd mkdir -p "$CONFIG_HOME"
  backup_if_needed "$TMUX_LINK" "$BACKUP_ROOT/tmux"
  link_config "$TMUX_SRC" "$TMUX_LINK"
}

setup_ghostty() {
  echo
  if ! confirm "Set up ghostty config?"; then
    echo "Skipping ghostty"
    return 0
  fi
  SETUP_GHOSTTY=1
  run_cmd mkdir -p "$CONFIG_HOME"
  backup_if_needed "$GHOSTTY_LINK" "$BACKUP_ROOT/ghostty"
  link_config "$GHOSTTY_SRC" "$GHOSTTY_LINK"
}

setup_zsh() {
  echo
  if ! confirm "Set up zsh config (p10k symlink + source zshrc)?"; then
    echo "Skipping zsh"
    return 0
  fi
  SETUP_ZSH=1
  backup_if_needed "$P10K_LINK" "$BACKUP_ROOT/p10k.zsh"
  link_config "$P10K_SRC" "$P10K_LINK"
  wire_zshrc
}

setup_configs() {
  echo
  echo "Choose which configs to set up (Enter = yes, n = skip):"
  setup_nvim
  setup_tmux
  setup_ghostty
  setup_zsh
}

# Extract leading X.Y or X.Y.Z from a version string.
normalize_version() {
  echo "$1" | grep -oE '[0-9]+(\.[0-9]+)+' | head -1
}

# Return 0 if version $1 >= minimum $2 (both numeric dotted).
version_ge() {
  local current="$1"
  local minimum="$2"
  [[ "$(printf '%s\n%s\n' "$minimum" "$current" | sort -V | head -1)" == "$minimum" ]]
}

# Warn if binary missing or older than minimum. Does not abort.
check_version() {
  local name="$1"
  local bin="$2"
  local minimum="$3"
  local version_flag="${4:---version}"

  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "Warning: $name not found. Config may not work; install $name >= $minimum."
    return 0
  fi

  local raw current
  raw="$("$bin" $version_flag 2>&1 | head -1)"
  current="$(normalize_version "$raw")"

  if [[ -z "$current" ]]; then
    echo "Warning: could not parse $name version from: $raw"
    return 0
  fi

  if version_ge "$current" "$minimum"; then
    echo "$name $current OK (>= $minimum)"
  else
    echo "Warning: $name $current is older than $minimum. Config may not work properly; please update $name to $minimum or newer."
  fi
}

check_versions() {
  if (( SETUP_NVIM == 0 && SETUP_TMUX == 0 && SETUP_GHOSTTY == 0 && SETUP_ZSH == 0 )); then
    return 0
  fi

  echo
  echo "Checking tool versions..."
  (( SETUP_NVIM )) && check_version "neovim" nvim "0.12.0"
  (( SETUP_TMUX )) && check_version "tmux" tmux "3.2" "-V"
  (( SETUP_GHOSTTY )) && check_version "ghostty" ghostty "1.0.0"
  (( SETUP_ZSH )) && check_version "zsh" zsh "5.8"
}

# --- main ---

parse_args "$@"
detect_os
install_packages
setup_configs
check_versions
