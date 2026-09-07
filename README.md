# dotfiles-iSH

Standalone, minimal iSH (iOS Alpine x86) dotfiles.

**Support:** experimental, below the Unix and Windows companions.

See [setup](docs/setup.md), [繁體中文安裝](docs/setup.zh-TW.md),
[tools](docs/tools.md), and [verification](docs/verification.md).

```sh
wget -O bootstrap.sh https://raw.githubusercontent.com/daviddwlee84/dotfiles-iSH/main/bootstrap.sh
sh bootstrap.sh
```

An existing checkout also works: `sh bootstrap.sh --config-only --manager sh`.
Use `sh bootstrap.sh --help` for optional tools and management modes.
No firmware, network policy or credentials are deployed.

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
