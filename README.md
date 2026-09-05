# Dotfiles

Single repo for nvim, tmux, ghostty, and zsh. `bootstrap.sh` installs dependencies, backs up existing configs into `backup/`, and links (or wires) everything into place.

## Setup

```bash
git clone <your-repo-url> ~/dotfiles
cd ~/dotfiles
./bootstrap.sh --dry-run   # optional preview
./bootstrap.sh
```

Then open a new terminal, or run `source ~/.zshrc` once.

## What bootstrap does

1. Detects apt / dnf / Homebrew and installs required tools (zsh, neovim, tmux, fzf, ripgrep, node, build tools, …). Homebrew is best-effort / untested.
2. If a managed config already exists (nvim, tmux, ghostty, or `~/.p10k.zsh`), it is moved into `backup/` and replaced with a symlink into this repo. If `backup/` already exists, you are asked whether to overwrite it; answering no aborts. Paths that are already linked here are left alone.
3. Symlinks:
   - `~/.config/nvim` → `nvim/`
   - `~/.config/tmux` → `tmux/`
   - `~/.config/ghostty` → `ghostty/`
   - `~/.p10k.zsh` → `zsh/p10k.zsh`
4. Ensures `~/.zshrc` sources `zsh/zshrc` (creates or appends one line). Does **not** replace or symlink `~/.zshrc`, so machine-local exports stay put.

## Layout

```
bootstrap.sh
nvim/          # neovim config
tmux/          # tmux.conf (TPM plugins install locally)
ghostty/
zsh/zshrc      # shared zsh (sourced from ~/.zshrc)
zsh/p10k.zsh
backup/        # created by bootstrap; gitignored
```
