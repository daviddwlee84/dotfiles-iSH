# ash keeps a builtin-only prompt; Bash may use the installed Starship.
case $- in *i*) ;; *) return 0;; esac
_dotfiles_net_label=${DOTFILES_NET_MODE:-auto}
case "$_dotfiles_net_label" in proxy|direct|auto) ;; *) _dotfiles_net_label=auto;; esac
case ${TERM:-dumb} in
    dumb) PS1='\u@\h:\w\$ '; unset _dotfiles_net_label; return 0 ;;
    *) PS1='\[\033[1;36m\]\u@\h\[\033[0m\] ['"$_dotfiles_net_label"'] \[\033[1;34m\]\w\[\033[0m\]\n\$ ' ;;
esac
unset _dotfiles_net_label
if [ -n "${BASH_VERSION:-}" ] && [ "${DOTFILES_PROMPT:-auto}" != plain ] && command -v starship >/dev/null 2>&1; then
    if _dotfiles_starship_init=$(starship init bash 2>/dev/null) && [ -n "$_dotfiles_starship_init" ]; then
        eval "$_dotfiles_starship_init"
    fi
    unset _dotfiles_starship_init
fi
