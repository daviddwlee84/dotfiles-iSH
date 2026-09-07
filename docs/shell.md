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

ash is the lightweight Almquist shell implementation in BusyBox. It interprets
commands and POSIX-style shell scripts. It is independent of chezmoi: chezmoi
manages files, while ash runs your commands. The iSH Alpine image and OpenWrt
use ash by default; Bash is optional.

A login ash reads system `/etc/profile`, then your `~/.profile`. Our managed block
loads the small shell fragment; it does not run installation/update commands.
See [setup](setup.md) for the profile contents and one-time migration. Both
platforms now default to chezmoi; subsequent configuration updates are simply
`chezmoi update`. Alpine's old native chezmoi package is not accepted just because
`--version` works: the source-layout capability must also pass.

References: [Starship guide](https://starship.rs/guide/),
[Starship releases](https://github.com/starship/starship/releases),
[Alpine v3.14 community x86 index](https://dl-cdn.alpinelinux.org/alpine/v3.14/community/x86/APKINDEX.tar.gz).
