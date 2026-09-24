# Ubuntu Config

Ubuntu environment configuration for:

- Kitty
- Neovim / LazyVim
- Fcitx5
- Zsh / Oh My Zsh
- JetBrainsMono Nerd Font

## New Ubuntu

Install git first:

    sudo apt update
    sudo apt install -y git

Clone this repository:

    git clone https://github.com/lsalex1/ubuntu-config.git ~/ubuntu-config
    cd ~/ubuntu-config
    chmod +x install.sh
    ./install.sh

## Managed configuration

- kitty -> ~/.config/kitty
- nvim -> ~/.config/nvim
- fcitx5 -> ~/.config/fcitx5
- zsh -> ~/.zshrc

JetBrainsMono Nerd Font is installed automatically by install.sh.

Fcitx5 user.history is intentionally not stored in this public repository.
