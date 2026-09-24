#!/usr/bin/env bash
set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-install}"

if [[ -f "$REPO_DIR/versions.env" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_DIR/versions.env"
else
  echo "[ERROR] $REPO_DIR/versions.env 不存在"
  exit 1
fi

NVIM_VERSION="${NVIM_VERSION:-v0.12.2}"
NERD_FONTS_VERSION="${NERD_FONTS_VERSION:-v3.5.1}"

required_files=(
  "kitty/.config/kitty/kitty.conf"
  "nvim/.config/nvim/init.lua"
  "fcitx5/.config/fcitx5/profile"
  "zsh/.zshrc"
  "versions.env"
)

check_repo() {
  echo "===== Repository check ====="
  local failed=0
  for f in "${required_files[@]}"; do
    if [[ -e "$REPO_DIR/$f" ]]; then
      echo "[OK]   $f"
    else
      echo "[MISS] $f"
      failed=1
    fi
  done

  echo
  echo "===== Kitty ====="
  grep -E '^(font_family|font_size)' "$REPO_DIR/kitty/.config/kitty/kitty.conf" || true

  echo
  echo "===== Versions ====="
  printf 'Neovim: %s\n' "$NVIM_VERSION"
  printf 'Nerd Fonts: %s\n' "$NERD_FONTS_VERSION"

  [[ "$failed" -eq 0 ]]
}

if [[ "$MODE" == "--check" || "$MODE" == "check" ]]; then
  check_repo
  exit $?
fi

if [[ "$MODE" != "install" && "$MODE" != "--link-only" && "$MODE" != "link-only" ]]; then
  echo "Usage:"
  echo "  ./install.sh"
  echo "  ./install.sh --check"
  echo "  ./install.sh --link-only"
  exit 2
fi

check_repo

mkdir -p "$HOME/.config" "$HOME/.local/bin" "$HOME/.local/opt" "$HOME/.local/share"

install_packages() {
  echo
  echo "===== Installing Ubuntu packages ====="

  if ! command -v apt-get >/dev/null 2>&1; then
    echo "[ERROR] 当前脚本仅支持 Ubuntu / Debian（需要 apt-get）"
    exit 1
  fi

  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git curl wget ca-certificates xz-utils tar unzip stow \
    zsh kitty fontconfig fonts-noto-cjk \
    fcitx5 fcitx5-chinese-addons fcitx5-config-qt \
    fcitx5-frontend-gtk3 fcitx5-frontend-gtk4 fcitx5-frontend-qt5 \
    im-config \
    ripgrep fd-find fzf build-essential \
    wl-clipboard xclip

  # Ubuntu 的 fd-find 可执行文件通常叫 fdfind。
  if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    ln -sfn "$(command -v fdfind)" "$HOME/.local/bin/fd"
  fi
}

install_neovim() {
  echo
  echo "===== Installing Neovim $NVIM_VERSION ====="

  local current=""
  if command -v nvim >/dev/null 2>&1; then
    current="$(nvim --version 2>/dev/null | awk 'NR==1{print $2}')"
  fi

  if [[ "$current" == "$NVIM_VERSION" ]]; then
    echo "[OK] 已安装相同版本 Neovim：$current"
    return
  fi

  local arch asset
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) asset="nvim-linux-x86_64.tar.gz" ;;
    aarch64|arm64) asset="nvim-linux-arm64.tar.gz" ;;
    *)
      echo "[ERROR] 不支持的架构：$arch"
      exit 1
      ;;
  esac

  local tmp url extracted target
  tmp="$(mktemp -d)"
  url="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${asset}"

  echo "下载：$url"
  curl -fL --retry 3 --connect-timeout 20 "$url" -o "$tmp/nvim.tar.gz"
  tar -xzf "$tmp/nvim.tar.gz" -C "$tmp"

  extracted="$(find "$tmp" -mindepth 1 -maxdepth 1 -type d -name 'nvim-*' -print -quit)"
  if [[ -z "$extracted" ]]; then
    echo "[ERROR] Neovim 解压目录未找到"
    rm -rf "$tmp"
    exit 1
  fi

  target="$HOME/.local/opt/neovim-${NVIM_VERSION}"
  rm -rf "$target"
  mv "$extracted" "$target"
  ln -sfn "$target/bin/nvim" "$HOME/.local/bin/nvim"
  rm -rf "$tmp"

  export PATH="$HOME/.local/bin:$PATH"
  nvim --version | head -1
}

install_font() {
  echo
  echo "===== Installing JetBrainsMono Nerd Font $NERD_FONTS_VERSION ====="

  if fc-match "JetBrainsMono Nerd Font" 2>/dev/null | grep -qi 'JetBrainsMono'; then
    echo "[OK] JetBrainsMono Nerd Font 已存在"
    return
  fi

  local font_dir tmp url
  font_dir="$HOME/.local/share/fonts/JetBrainsMono"
  tmp="$(mktemp --suffix=.tar.xz)"
  url="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VERSION}/JetBrainsMono.tar.xz"

  mkdir -p "$font_dir"
  echo "下载：$url"
  curl -fL --retry 3 --connect-timeout 20 "$url" -o "$tmp"
  tar -xf "$tmp" -C "$font_dir"
  rm -f "$tmp"
  fc-cache -f

  fc-match "JetBrainsMono Nerd Font"
}

clone_plugin() {
  local name="$1"
  local url="$2"
  local dst="$HOME/.oh-my-zsh/custom/plugins/$name"

  if [[ -d "$dst/.git" ]]; then
    echo "[OK] $name 已存在"
    return
  fi

  if [[ -e "$dst" ]]; then
    mv "$dst" "${dst}.backup.$(date +%Y%m%d-%H%M%S)"
  fi

  git clone --depth=1 "$url" "$dst"
}

install_zsh_stack() {
  echo
  echo "===== Installing Oh My Zsh and plugins ====="

  if [[ ! -d "$HOME/.oh-my-zsh/.git" ]]; then
    if [[ -e "$HOME/.oh-my-zsh" ]]; then
      mv "$HOME/.oh-my-zsh" "$HOME/.oh-my-zsh.backup.$(date +%Y%m%d-%H%M%S)"
    fi
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
  else
    echo "[OK] Oh My Zsh 已存在"
  fi

  clone_plugin zsh-autosuggestions \
    https://github.com/zsh-users/zsh-autosuggestions.git
  clone_plugin zsh-syntax-highlighting \
    https://github.com/zsh-users/zsh-syntax-highlighting.git
  clone_plugin zsh-completions \
    https://github.com/zsh-users/zsh-completions.git
}

backup_target() {
  local target="$1"
  local backup_root="$2"

  if [[ ! -e "$target" && ! -L "$target" ]]; then
    return
  fi

  # 已经由本仓库管理的链接不再备份。
  if [[ -L "$target" ]]; then
    local resolved=""
    resolved="$(readlink -f "$target" 2>/dev/null || true)"
    if [[ "$resolved" == "$REPO_DIR/"* ]]; then
      echo "[SKIP] 已由仓库管理：$target"
      return
    fi
  fi

  local rel="${target#$HOME/}"
  mkdir -p "$backup_root/$(dirname "$rel")"
  echo "[BACKUP] $target"
  mv "$target" "$backup_root/$rel"
}

backup_configs() {
  echo
  echo "===== Backing up existing configs ====="

  local backup_root
  backup_root="$HOME/.ubuntu-config-backups/$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$backup_root"

  backup_target "$HOME/.config/kitty" "$backup_root"
  backup_target "$HOME/.config/nvim" "$backup_root"
  backup_target "$HOME/.config/fcitx5" "$backup_root"
  backup_target "$HOME/.zshrc" "$backup_root"

  echo "[OK] 备份目录：$backup_root"
}

link_configs() {
  echo
  echo "===== Linking configs with GNU Stow ====="

  if ! command -v stow >/dev/null 2>&1; then
    echo "[ERROR] GNU Stow 未安装。请先执行：sudo apt install -y stow"
    exit 1
  fi

  cd "$REPO_DIR"
  stow --restow --target="$HOME" kitty nvim fcitx5 zsh
}

finish_setup() {
  echo
  echo "===== Final setup ====="

  if command -v im-config >/dev/null 2>&1; then
    im-config -n fcitx5 || true
  fi

  mkdir -p "$HOME/.config/autostart"
  if [[ -f /usr/share/applications/org.fcitx.Fcitx5.desktop ]]; then
    cp -f /usr/share/applications/org.fcitx.Fcitx5.desktop \
      "$HOME/.config/autostart/"
  fi

  fc-cache -f >/dev/null 2>&1 || true

  local zsh_path=""
  zsh_path="$(command -v zsh || true)"
  if [[ -n "$zsh_path" ]]; then
    local login_shell=""
    login_shell="$(getent passwd "$USER" | cut -d: -f7)"
    if [[ "$login_shell" != "$zsh_path" ]]; then
      echo "准备把默认 Shell 设置为：$zsh_path"
      chsh -s "$zsh_path" || {
        echo "[WARN] chsh 没有成功。稍后可手动执行：chsh -s $zsh_path"
      }
    fi
  fi

  echo
  echo "===== Result ====="
  echo "Kitty:"
  grep -E '^(font_family|font_size)' "$HOME/.config/kitty/kitty.conf" || true
  echo
  echo "Font:"
  fc-match "JetBrainsMono Nerd Font" || true
  echo
  echo "Neovim:"
  PATH="$HOME/.local/bin:$PATH" nvim --version 2>/dev/null | head -1 || true
  echo
  echo "Zsh:"
  zsh --version 2>/dev/null || true
  echo
  echo "Fcitx5:"
  fcitx5 --version 2>/dev/null | head -1 || true

  echo
  echo "安装完成。建议注销 Ubuntu 后重新登录一次。"
}

if [[ "$MODE" == "install" ]]; then
  install_packages
  install_neovim
  install_font
  install_zsh_stack
fi

backup_configs
link_configs

if [[ "$MODE" == "install" ]]; then
  finish_setup
else
  echo
  echo "[OK] 仅建立配置链接，没有安装或更新软件。"
fi
