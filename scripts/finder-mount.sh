#!/bin/sh
# managed-by: dotfiles-lite-finder; create-once runtime helper
# Standalone at boot: no checkout, user profile or chezmoi dependency.
set -eu
finder_error() { printf '[dotfiles] %s\n' "$*" >&2; exit 1; }
finder_sysroot=''
if [ -n "${DOTFILES_TEST_ROOT:-}" ]; then
    [ "${DOTFILES_TEST_MODE:-}" = fixture-only-v1 ] || finder_error 'Invalid Finder fixture mode'
    case "$DOTFILES_TEST_ROOT" in /*) ;; *) finder_error 'Invalid Finder fixture root' ;; esac
    [ "$DOTFILES_TEST_ROOT" != / ] && [ -f "$DOTFILES_TEST_ROOT/.fixture" ] &&
        [ "$HOME" = "$DOTFILES_TEST_ROOT/home" ] || finder_error 'Finder fixture HOME must be isolated'
    finder_sysroot=$DOTFILES_TEST_ROOT
fi
[ -d "$finder_sysroot/proc/ish" ] || finder_error 'Finder mount requires iSH.'
finder_action=${1:-mount}
case "$finder_action" in mount|check|status) ;; *) finder_error 'Usage: dotfiles-finder [mount|check|status]' ;; esac
[ "$#" -le 1 ] || finder_error 'Unexpected Finder mount arguments'
finder_target="$finder_sysroot/mnt/finder"
finder_mount_bin="$finder_sysroot/bin/mount"
for finder_path in "$finder_sysroot/mnt" "$finder_target"; do
    [ ! -L "$finder_path" ] || finder_error 'Finder mount preserves symlink at /mnt or /mnt/finder.'
    [ ! -e "$finder_path" ] || [ -d "$finder_path" ] || finder_error 'Finder mountpoint is not a directory.'
done
finder_source=$(cat "$finder_sysroot/proc/ish/documents") || finder_error 'Cannot read /proc/ish/documents.'
case "$finder_source" in /*) ;; *) finder_error 'iSH Documents path is empty or not absolute.' ;; esac
[ -r "$finder_sysroot/proc/mounts" ] || finder_error 'Cannot inspect /proc/mounts.'

finder_mount_state() {
    DOTFILES_FINDER_SOURCE="$finder_source" DOTFILES_FINDER_TARGET="$finder_target" awk '
        function escaped(s, result, i, c) {
            result=""
            for (i=1; i<=length(s); i++) {
                c=substr(s,i,1)
                if (c=="\\") result=result "\\134"
                else if (c==" ") result=result "\\040"
                else if (c=="\t") result=result "\\011"
                else if (c=="\n") result=result "\\012"
                else result=result c
            }
            return result
        }
        BEGIN {
            source=ENVIRON["DOTFILES_FINDER_SOURCE"]; alternate=source
            if (source ~ /^\/private\/var\//) sub(/^\/private/, "", alternate)
            else if (source ~ /^\/var\//) alternate="/private" source
            source=escaped(source); alternate=escaped(alternate)
            target=escaped(ENVIRON["DOTFILES_FINDER_TARGET"])
        }
        $2==target {
            count++
            if ($3=="real" && ($1==source || $1==alternate)) matching++
        }
        index($2,target "/")==1 { nested=1 }
        END {
            if (nested || count>1 || (count==1 && matching!=1)) print "conflict"
            else if (count==1) print "mounted"
            else print "absent"
        }
    ' "$finder_sysroot/proc/mounts"
}

case "$(finder_mount_state)" in
    mounted) printf '[dotfiles] Finder files mounted at /mnt/finder.\n'; exit 0 ;;
    conflict) finder_error 'Existing mount at or below /mnt/finder preserved; resolve the conflict or use --finder off.' ;;
    absent) ;;
    *) finder_error 'Could not determine Finder mount state.' ;;
esac
if [ "$finder_action" = status ]; then
    printf '[dotfiles] Finder files are not mounted.\n'
    exit 1
fi
if [ -d "$finder_target" ]; then
    ls -A "$finder_target" >/dev/null || finder_error 'Cannot inspect /mnt/finder.'
    for finder_entry in "$finder_target"/* "$finder_target"/.[!.]* "$finder_target"/..?*; do
        [ ! -e "$finder_entry" ] && [ ! -L "$finder_entry" ] || finder_error 'Nonempty /mnt/finder preserved; move its contents yourself or use --finder off.'
    done
fi
[ -x "$finder_mount_bin" ] || finder_error "Finder prerequisite missing: $finder_mount_bin"
command -v timeout >/dev/null 2>&1 || finder_error 'BusyBox timeout is required for Finder mounting.'
[ "$finder_action" != check ] || exit 0
[ "$(id -u)" = 0 ] || finder_error 'Finder mounting requires root.'
mkdir -p "$finder_target"
timeout -s KILL 15 "$finder_mount_bin" -t real "$finder_source" "$finder_target" || finder_error 'Finder mount failed or timed out; existing mounts were not removed.'
[ "$(finder_mount_state)" = mounted ] || finder_error 'Finder mount could not be verified in /proc/mounts.'
printf '[dotfiles] Finder files mounted at /mnt/finder.\n'
