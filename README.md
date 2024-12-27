# Dotfiles

I track my dotfiles in this bare repo, stored in my home directory.

## How to Create Your Own

Within your home directory, initialize a bare repo:
```bash
git init --bare ~/.dotfiles
```

Create an alias in your `~/.zshrc` or `~/.bashrc` so you don't have to type out `git --git-dir=... --work-tree=...` every time:
```bash
alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
```

Ignore untracked files (so Git doesn't track every file in your home directory):
```bash
dotfiles config --local status.showUntrackedFiles no
```

Add and commit your configs:
```bash
# For example...
dotfiles add .zshrc
dotfiles add .config/lvim/config.lua
dotfiles add .config/ghostty/config
dotfiles add .tmux.conf
# ...and so forth
dotfiles commit -m "Adding dotfiles"
```

Push to remote:
```bash
dotfiles remote add origin git@github.com:yourusername/dotfiles.git
dotfiles push
```

## How to Sync on a New Machine

Clone (bare) into .dotfiles:
```bash
git clone --bare git@github.com:yourusername/dotfiles.git $HOME/.dotfiles
```

Re-create the alias and checkout:
```bash
alias dotfiles='/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME'
dotfiles checkout
dotfiles config --local status.showUntrackedFiles no
```
