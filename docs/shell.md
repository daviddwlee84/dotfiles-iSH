# Shell and Starship

The default login shell remains ash. Interactive ash gets a colored two-line
prompt using shell builtins only, without per-prompt binary execution or a Nerd
Font requirement. Noninteractive shells retain clean output. Personal local.sh
is loaded last and can override PS1.

```sh
sh bootstrap.sh --with starship
. ~/.profile
bash
```

Starship's supported Bash initialization runs in Bash, not ash. The optional
selection installs Bash and a small Starship preset (username, hostname, directory,
status character; no language/runtime scans). Type `bash` to enter it and `exit`
to return to ash. No chsh or automatic shell replacement occurs. Existing
`~/.config/starship.toml` is a seed and remains untouched; `.bashrc` receives only
the standard managed source block. `DOTFILES_PROMPT=plain bash` skips Starship.

On OpenWrt, Starship uses the locked ARM64/x86_64 musl release. On iSH, it uses
the current Alpine feed package instead of assuming a modern Rust binary works
in the emulator. The v3.14 community index contains Starship 0.54.0 and chezmoi
2.0.16. Package availability is not emulator acceptance: iSH Starship/chezmoi
remain experimental until tested on the actual device. The ash prompt remains
usable even when an optional binary fails.

To update a previously downloaded source snapshot, first download the new standalone
bootstrap and run `sh bootstrap.sh --update-source --with starship`. The flag must
come first. It preserves the previous snapshot in a printed sibling backup path;
Git checkouts are never replaced (use git pull --ff-only there).

The initial iSH `Configuration manager: sh` output is expected: auto retains the
chosen sh manager. To select chezmoi explicitly, use
`sh bootstrap.sh --manager chezmoi`. The installer uses a compatible locked i386
binary; Alpine 3.14's older package predates source features this repository uses.
A version-only probe no longer accepts that incompatible installation.

References: [Starship guide](https://starship.rs/guide/),
[Starship releases](https://github.com/starship/starship/releases),
[Alpine v3.14 community x86 index](https://dl-cdn.alpinelinux.org/alpine/v3.14/community/x86/APKINDEX.tar.gz).
