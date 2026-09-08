# Setup and management

**chezmoi is the default on both lightweight platforms.** Bootstrap is the first
installation/migration entrypoint; daily configuration updates use chezmoi.
The target needs only `/bin/sh` (BusyBox ash) and an HTTPS downloader initially.

## First installation or migration from the old sh installer

Download the current entrypoint on the device, even if an older bootstrap exists:

```sh
wget -O bootstrap.sh https://raw.githubusercontent.com/daviddwlee84/dotfiles-iSH/main/bootstrap.sh
sh bootstrap.sh
. ~/.profile
```

Then use the familiar commands:

```sh
chezmoi diff
chezmoi apply
chezmoi update
```

`chezmoi update` pulls the source with `git pull --ff-only`, installs missing
baseline/selected optional packages via native apk/opkg, then applies the home
configuration. It does not upgrade existing packages or working tool binaries.
A failed pull stops before applying. Divergent commits or conflicting source edits
remain for you to resolve; the updater does not auto-stash, commit or push.

The standalone entrypoint obtains a temporary source snapshot for installation
prerequisites, then creates a real Git checkout at
`~/.local/share/dotfiles-iSH`, tracking `origin/main`. Existing snapshots are
retained in printed sibling backup paths, including any custom source files;
the newly active source is the upstream checkout. Review/copy intentional source
customizations from the backup before updating them with chezmoi. Existing Git
checkouts are reused, never replaced. Older sh installations migrate to chezmoi
when run through the current entrypoint. The legacy `--update-source` flag remains
accepted for snapshot refresh but is unnecessary for daily updates.

If curl is available, `curl -fLsS -o bootstrap.sh URL` is equivalent; OpenWrt can
also use `uclient-fetch -O bootstrap.sh URL`. Keep TLS verification enabled.
`DOTFILES_REF` can pin a tag/commit instead of main; that produces a detached
checkout, so return to a tracking branch before using `chezmoi update`.

## Options and offline use

```sh
sh bootstrap.sh --with starship
sh bootstrap.sh --with dev,starship
sh bootstrap.sh --dry-run
sh bootstrap.sh --doctor
sh bootstrap.sh --manager sh --config-only
```

The default manager is `chezmoi`; `auto` is a compatibility alias for it. A usable
installed chezmoi is retained, otherwise bootstrap downloads the locked official
binary and verifies its hash and bounded capability probe. Failure stops with an
explicit `--manager sh` recovery suggestion; it never silently selects sh.
Alpine 3.14's native chezmoi 2.0.16 lacks this repository's source-layout features.
The locked modern i386 release remains experimental until tested on actual iSH.

Use `--manager sh` for an explicit lightweight alternative. Both managers deploy
the same home files. After any later default bootstrap run, chezmoi is selected
again. `--config-only` skips packages, tool downloads and Git migration; from an
existing copied source it works offline. An offline snapshot can be applied but
cannot use `chezmoi update` until an online bootstrap prepares Git.
`--dry-run` previews the manifest without writes; use `chezmoi diff` for real diffs.

Optional choices are saved in `~/.local/state/dotfiles-lite/options`. Omitting
`--with` retains them; an explicit list replaces the selection without uninstalling
anything. OpenWrt also accepts `herdr,specstory,codex`. Optional failure returns
nonzero after preserving a working baseline; baseline-package failure stops
before configuration. Packages already successfully added remain installed.

## Source and package connectivity

`--source-network inherit|direct|proxy` controls Git and tool downloads; proxy
requires an existing authenticated Nikki on OpenWrt. `--package-network
inherit|direct` independently controls native package calls. Defaults are inherit.
Successful setup saves these **nonsecret choices** for plain `chezmoi update`;
proxy credentials are read only at execution time and never stored in dotfiles.

`DOTFILES_SOURCE_NETWORK` and `DOTFILES_PACKAGE_NETWORK` override the saved choice
for a command. To change the saved preference, rerun the source's bootstrap with
the desired flags. Existing custom `[update]` configuration is preserved; the
network-aware updater is configured automatically only when no custom update
section exists. See the OpenWrt network guide for initial GitHub reachability.

## What chezmoi owns

`.chezmoiroot` selects only `home/`. Repository metadata and scripts stay in the
source checkout. `~/.config/chezmoi/chezmoi.toml` points to that checkout and
selects its update script. Older same-source configs gain only the update section,
with a backup; unrelated chezmoi sources are never taken over.

`~/.profile` is the login-shell entrypoint. The installer preserves its existing
content and appends one block loading `~/.config/dotfiles-lite/profile.sh`.
That fragment adds `~/.local/bin` to PATH, defaults EDITOR/PAGER, loads interactive
aliases and the prompt, then loads your optional `~/.config/dotfiles-lite/local.sh`
last. Put personal overrides there; it is never created or tracked. No download,
package installation or chezmoi update runs when you open a shell.

SSH, tmux and Starship configs are create-once seeds. Git identity and credentials
remain yours. See [Shell and Starship](shell.md) for ash versus Bash.

With an already compatible chezmoi and working Git/network, direct initialization
also works and uses the same package/apply hooks:

```sh
chezmoi init --apply https://github.com/daviddwlee84/dotfiles-iSH.git
```

Upgrading tool binaries remains explicit: maintainers update the version, URL,
hash, member and size in `config/assets.lock` together and validate in CI. Existing
working versions are kept. Herdr upgrades belong outside Herdr panes and follow
upstream's session-preserving procedure.

If a probe stalls or you want to upgrade Alpine, see [system upgrades](system-upgrade.md).

## SSH server on iSH

SSH preparation is on by default, before the chezmoi runtime check. Use
`--sshd off` to opt out or `--prepare-sshd` for SSH-only setup without chezmoi.
Direct `chezmoi init` asks for the choice; unattended init uses `--promptDefaults`.
OpenRC autostart, manual login setup, ownership and recovery are documented in
[SSH server](ssh-server.md). Local agents are tracked in [experiments](experiments.md).

## Finder shared files

Finder's iSH Documents directory is mounted at `/mnt/finder` by default, with an
independent OpenRC service restoring it at app startup. `chezmoi init` asks for
the choice; `--finder off` opts out. Use `--prepare-finder` for just this setup,
without chezmoi or SSH changes. Existing contents and foreign mounts are
preserved. See [Finder files](finder-files.md) for transfer, ownership and checks.
