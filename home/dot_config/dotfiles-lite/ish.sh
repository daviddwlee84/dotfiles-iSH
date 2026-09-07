# iSH-only helpers. Mounted vault and user-specific configuration are not managed.
OBSIDIAN_MNT=${OBSIDIAN_MNT:-/mnt/dq/Obsidian}
export OBSIDIAN_MNT
_ovault_mounted() {
    [ -d "$OBSIDIAN_MNT" ] && [ -n "$(ls -A "$OBSIDIAN_MNT" 2>/dev/null)" ]
}
ovault() {
    mkdir -p "$OBSIDIAN_MNT" || return 1
    if ! _ovault_mounted; then
        printf 'Select your vault folder in iOS Files: %s\n' "$OBSIDIAN_MNT"
        mount -t ios null "$OBSIDIAN_MNT" || return 1
    fi
    cd "$OBSIDIAN_MNT${1:+/$1}" || return 1
    if [ -d .git ] || [ -f .git ]; then
        _ov_repo=$(pwd -P)
        git config --global --get-all safe.directory 2>/dev/null | grep -qxF "$_ov_repo" ||
            git config --global --add safe.directory "$_ov_repo" || return 1
        unset _ov_repo
    fi
}
ovsync() {
    ovault "${1:-}" || return 1
    git rev-parse --show-toplevel >/dev/null 2>&1 || { echo 'Not a Git repository' >&2; return 1; }
    git add -A || return 1
    if ! git diff --cached --quiet; then
        git commit -m "${2:-notes: sync from iOS $(date '+%F %H:%M')}" || return 1
    fi
    if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
        git pull --rebase --autostash || return 1
        git push
    else
        git push -u origin HEAD
    fi
}
