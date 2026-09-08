# dotfiles-iSH

Standalone, minimal iSH (iOS Alpine x86) dotfiles.

**Support:** experimental, below the Unix and Windows companions.

See [setup](docs/setup.md), [繁體中文安裝](docs/setup.zh-TW.md),
[tools](docs/tools.md), and [verification](docs/verification.md).

```sh
wget -O bootstrap.sh https://raw.githubusercontent.com/daviddwlee84/dotfiles-iSH/main/bootstrap.sh
sh bootstrap.sh
. ~/.profile
# Subsequent updates:
chezmoi update
```

**Default: chezmoi with a Git checkout.** Existing sh/snapshot installs migrate through
the current bootstrap; the full previous source is retained in a sibling backup.

An explicit offline sh checkout also works: `sh bootstrap.sh --config-only --manager sh`.
Use `sh bootstrap.sh --help` for optional tools and management modes.
No firmware or network policy is deployed. iSH SSH setup is enabled by default;
host keys are generated locally and passwords remain manual. See
[SSH server](docs/ssh-server.md) / [SSH 伺服器](docs/ssh-server.zh-TW.md).
Finder file sharing is also enabled by default at `/mnt/finder`, with mounting
at iSH startup. Use `--finder off` to opt out; see
[Finder files](docs/finder-files.md) / [Finder 檔案共享](docs/finder-files.zh-TW.md).
The experimental i386 Herdr build and its release gate are documented in
[Herdr on iSH](docs/herdr-ish.md) / [iSH 上的 Herdr](docs/herdr-ish.zh-TW.md).

<!-- project-knowledge-harness:readme-roadmap -->
<!-- Snippet for project's README.md, placed near other meta sections like
     "Customization" or "Contributing". -->

## Roadmap & lessons learned

Forward-looking work — long-term ideas, deferred items, things needing
evaluation — lives in [`TODO.md`](TODO.md), prioritised P1 → P3 with effort
estimates (S/M/L/XL). Items with accompanying research, design notes, or paused
troubleshooting link to a corresponding [`backlog/<slug>.md`](backlog/) doc.

Backward-looking knowledge — past traps and non-obvious debugging — lives in
[`pitfalls/`](pitfalls/), titled by symptom so future-you can grep the error
message and land on the root cause + workaround instead of re-debugging from
scratch.
<!-- project-knowledge-harness:readme-roadmap --> (end)

Shell: ash now has a colored builtin prompt. Opt in with `--with starship`,
then enter `bash` for Starship; see [shell](docs/shell.md) / [繁中](docs/shell.zh-TW.md).
