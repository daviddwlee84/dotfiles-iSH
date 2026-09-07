# Setup and management

This repository manages a small personal shell environment. The bootstrap runs
with `/bin/sh` (BusyBox ash); it does not require Bash, Python, Ansible or just.

## First installation

Run on the target device:

```sh
wget -O bootstrap.sh https://raw.githubusercontent.com/daviddwlee84/dotfiles-iSH/main/bootstrap.sh
sh bootstrap.sh
```

If curl is already available, `curl -fLsS -o bootstrap.sh URL` is equivalent.
On OpenWrt without wget, use `uclient-fetch -O bootstrap.sh URL`. These clients
must support HTTPS and trust the server certificate; never disable verification.
If download tools or connectivity are unavailable, copy an unpacked checkout to
the device and run its `bootstrap.sh`. The standalone entrypoint downloads a
GitHub source snapshot into `~/.local/share/dotfiles-iSH`; it reuses an existing
source and never replaces a customized checkout. `DOTFILES_REF` may name a tag
or commit instead of `main` when fetching a new source.

## Choose a manager

```sh
sh bootstrap.sh --dry-run
sh bootstrap.sh --manager sh
sh bootstrap.sh --manager chezmoi
sh bootstrap.sh --config-only --manager sh
sh bootstrap.sh --doctor
```

`auto` is the default: iSH selects sh; OpenWrt uses a working chezmoi or attempts
the locked official binary. If chezmoi cannot be obtained on a first OpenWrt
setup, configuration uses sh instead. An explicit `--manager chezmoi` failure
stops. Successful selection is recorded in `~/.local/state/dotfiles-lite/manager`;
later auto runs retain it. Switching managers requires the explicit flag.
A failing config apply never silently switches managers.

`--config-only` skips packages and downloads, allowing offline configuration.
`--dry-run` is a read-only manifest preview (not a line-by-line diff). For a real
chezmoi configuration diff after setup, run `chezmoi diff`. sh preserves conflicting
managed edits and asks you to compare the source with the target before retrying.

For a compatible modern chezmoi installation (verified with 2.72.1), the repository is also directly usable. Alpine 3.14's 2.0.16 lacks the source-layout features; use bootstrap instead of this direct command:

```sh
chezmoi init --apply https://github.com/daviddwlee84/dotfiles-iSH.git
```

The official one-line installation path is supported when curl and network access
already work. This path has no sh fallback because chezmoi owns that invocation:

```sh
GITHUB_USERNAME=daviddwlee84
sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin" init --apply "https://github.com/$GITHUB_USERNAME/dotfiles-iSH.git"
```

The official installer tracks upstream; `bootstrap.sh` instead verifies the
repo's locked chezmoi asset. Existing unrelated chezmoi configuration is never
taken over by bootstrap. Use sh or explicitly migrate that source yourself.

## Ownership and updates

Only `home/` is a chezmoi source (`.chezmoiroot`). The sh path deploys the exact
same source files through `config/files.list`; README, history, skills, scripts,
locks and backlog never enter HOME. A managed profile fragment is sourced from
an appended `.profile` block. SSH and tmux are first-run seeds; Git identity and
credentials are left to you. Put personal overrides in
`~/.config/dotfiles-lite/local.sh` (not created or tracked).

Installs do not upgrade existing packages or working tool binaries. Source
updates are explicit: `git pull --ff-only` in a Git checkout; for a snapshot,
use a newly downloaded bootstrap with --update-source to retain the old source
in a sibling backup before replacing it. Updating configs and upgrading binaries are separate decisions.
Refresh version/URL/hash/member/size together in `config/assets.lock`, validate
in CI, then explicitly replace an old binary when ready. A Herdr update belongs
outside any Herdr pane and must follow its own session-preserving update procedure.

Optional choices are supplied with `--with dev` or `--with starship` (OpenWrt also accepts
`herdr,specstory,codex`). Repeated flags are accepted. Without `--with`, prior
choices are retained; an explicit list replaces the recorded selection, without
uninstalling anything. Optional failure returns nonzero after preserving a working
baseline; baseline-package failure stops before configuration. Installation is
not an atomic package transaction; packages already added remain installed.

See [Shell and Starship](shell.md) for the ash prompt, optional Bash setup,
chezmoi package compatibility and explicit snapshot updates.

`--package-network direct` (or `DOTFILES_PACKAGE_NETWORK=direct`) clears app proxy
variables only inside package-manager calls; binary/source downloads retain the
caller environment. Default `inherit` never silently changes the chosen route.

Bootstrap renders its sourceDir config and applies it without init, so a downloaded snapshot stays a snapshot.
The official repo-URL initialization still creates a normal Git checkout.
