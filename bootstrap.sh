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

backup_and_link() {
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

  echo
  echo "Backing up existing configs to $BACKUP_ROOT"
  run_cmd mkdir -p "$BACKUP_ROOT"

  backup_if_needed "$NVIM_LINK" "$BACKUP_ROOT/nvim"
  backup_if_needed "$TMUX_LINK" "$BACKUP_ROOT/tmux"
  backup_if_needed "$GHOSTTY_LINK" "$BACKUP_ROOT/ghostty"
  backup_if_needed "$P10K_LINK" "$BACKUP_ROOT/p10k.zsh"

  echo
  echo "Creating symlinks..."
  run_cmd mkdir -p "$CONFIG_HOME"

  link_config "$NVIM_SRC" "$NVIM_LINK"
  link_config "$TMUX_SRC" "$TMUX_LINK"
  link_config "$GHOSTTY_SRC" "$GHOSTTY_LINK"
  link_config "$P10K_SRC" "$P10K_LINK"
}

wire_zshrc() {
  local line="source \"$ZSHRC_SRC\""

  echo
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

# --- main ---

parse_args "$@"
detect_os
install_packages
backup_and_link
wire_zshrc
