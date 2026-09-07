# Minimal shared shell configuration; ash has no prompt-time subprocesses.
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) PATH="$HOME/.local/bin:$PATH" ;; esac
export PATH
EDITOR=${EDITOR:-vi}
PAGER=${PAGER:-less}
export EDITOR PAGER
case $- in *i*) alias ll='ls -al'; alias g='git';; esac
# Existing inline ish-bootstrap helpers remain authoritative during migration.
if [ -r "$HOME/.config/dotfiles-lite/ish.sh" ] && ! command -v ovault >/dev/null 2>&1; then
    . "$HOME/.config/dotfiles-lite/ish.sh"
fi
if [ -r "$HOME/.config/dotfiles-lite/prompt.sh" ]; then
    . "$HOME/.config/dotfiles-lite/prompt.sh"
fi
if [ -r "$HOME/.config/dotfiles-lite/local.sh" ]; then
    . "$HOME/.config/dotfiles-lite/local.sh"
fi
