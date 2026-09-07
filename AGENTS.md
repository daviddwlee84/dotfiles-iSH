# Agent contract

This is a standalone, experimental dotfiles-iSH repository. Support priority is
Unix > Windows >> iSH / OpenWrt. Keep the target baseline small.

- Read README.md and bilingual docs/setup.md + docs/setup.zh-TW.md before changing installation.
- bootstrap.sh and scripts/{manage,core}.sh run in BusyBox ash. No Bash, Python,
  Ansible, just, Node or chezmoi prerequisite on the target.
- scripts/core.sh, scripts/manage.sh, scripts/update.sh, tests/bootstrap.bats,
  config/chezmoi-update.toml.tmpl and config/assets.lock
  are mirrored verbatim in the other lightweight companion. Update both together.
- home/ is the chezmoi source; config/files.list explicitly maps those SAME source
  files for sh deployment. Test both managers after changing a managed file.
- Preserve user state. No system upgrades, feed replacement, login-shell changes,
  credential writes, service enable/restart, UCI/network/firewall changes or
  automatic git commits/pushes on target devices.
- ash has a builtin-only prompt; Starship uses upstream Bash initialization. No chsh or automatic exec bash.
- Default manager is chezmoi; auto is an alias. First online setup migrates snapshots
  to a real tracking Git checkout and retains the full previous source in a backup.
  Daily chezmoi update uses a fast-forward-only pull, then the native package/apply hooks.
  Source/package network preferences are nonsecret local state; never persist proxy auth.
- Installs are install-only. Release URLs/architecture/member/SHA-256/size are
  locked in config/assets.lock. Never bypass a failed checksum or runtime probe.
- Existing SSH/tmux configs are seeds; never overwrite them. Preserve legacy
  iSH helpers and user profile content. Runtime local.sh is never managed.
- Herdr settings belong to Herdr/user; do not copy the full Unix overlay or
  install helpers/plugins whose dependencies are absent.
- Tests use isolated HOME + fixture-only-v1; never run target bootstrap on the
  maintainer machine outside the fixture harness.
- Run just check (ShellCheck, Bats, strict bilingual MkDocs). CI musl probes do
  not establish iSH emulator or OpenWrt hardware support. Record verification levels.
- New user docs have an English/zh-TW pair and nav + nav_translations entries.
- Public commits run secret checks. Never add private runtime state or auth.
- Source provenance: iSH behavior/docs migrated from daviddwlee84/dotfiles@4073f2207afb0c865b58321f46c2edfb16c7819c.

<!-- project-knowledge-harness:agent-guidance -->
<!-- Snippet for the project's agent contract file (AGENTS.md / CLAUDE.md /
     similar). The bundled scripts/init.sh appends this between sentinel
     markers; safe to re-run. -->

### Long-term backlog → `TODO.md` + `backlog/`

When the user surfaces an idea explicitly **not** being implemented this
session (signals: "maybe later", "nice to have", "if I'm interested",
"工程量太大需要再評估", "先記下來"), add an entry to [`TODO.md`](TODO.md) using
the priority + effort tag schema. Do **not** create new `ROADMAP.md` /
`IDEAS.md` / `BACKLOG.md` files — `TODO.md` is the single index.

The bundled `scripts/todo-kanban.sh` validates the format. Run it
(`scripts/todo-kanban.sh --validate-only TODO.md`) after editing so syntax
drift is caught immediately.

#### Three ways to add a TODO entry (preferred order)

1. **Structured CLI — `scripts/add-todo.sh`** (default):

   ```
   scripts/add-todo.sh --priority P3 --effort M \
     --title "Title" --description "Description"
   ```

   Inserts a canonically-formatted line into the right `## P*` lane and
   re-runs the validator. Add `--backlog` to also scaffold
   `backlog/<slug>.md` from the bundled template.

2. **Quick capture — `backlog/inbox.md`** (when priority/effort unclear):

   ```
   echo "- maybe add docs versioning with mike" >> backlog/inbox.md
   ```

   When the user asks "sweep the inbox", run
   `scripts/sweep-inbox.sh`. It prompts for the missing fields per loose
   line and calls `add-todo.sh`. Use `--batch` for non-interactive runs
   that only formalize lines with parseable `key=value` pairs.

3. **Direct edit of `TODO.md`** — fine if the format is fresh; run
   `scripts/todo-kanban.sh --validate-only` afterwards.

Add a `backlog/<slug>.md` companion doc when the item meets any of:

- carries a `P?` tag (record what was tried so it doesn't need re-investigation)
- captures a paused troubleshooting session that you intend to fix later
  (preserve the error trace + root cause analysis before context evaporates)
- weighs multiple options (record trade-offs, not only the winner)
- is `[L]` or `[XL]` (architectural; needs design before code)

`[S]` items rarely need a backlog doc — a file path in the `TODO.md` line is
usually enough. See [`backlog/README.md`](backlog/README.md) for the full
template and "when to add a doc" rules.

When implementing a `TODO.md` item, in the same commit:

1. Run `scripts/promote-todo.sh --title "<substring>" --summary "<what shipped>"`
   to move the entry into `## Done` with the dated syntax and re-validate.
2. Mark the corresponding `backlog/<slug>.md` (if any) `Status: shipped`
   and keep it as a historical record (don't delete — future-you may
   revisit adjacent decisions).

`backlog/` is excluded from chezmoi (see .chezmoiignore.tmpl); it
is repo metadata for maintainers, not user-facing config to deploy.

### Past pitfalls → `pitfalls/`

When you spend more than ~15 minutes debugging something that wasn't
googleable and the fix is non-obvious, write a `pitfalls/<slug>.md`
capturing:

1. **Verbatim symptom** — copy-paste error messages exactly, do not
   paraphrase (preserves grep-ability for future-you / future agent)
2. **Root cause** — why this happens (with source / docs / upstream issue link)
3. **Workaround** — copy-pasteable commands or config diff
4. **Prevention** — how to avoid stepping on this again

Title the doc by the **symptom**, not the root cause (you'll search by what
you're seeing, not by what you eventually learned). See
[`pitfalls/README.md`](pitfalls/README.md) for the full template and
when-to-add rules.

**Pitfall vs Hard invariant**: a pitfall *graduates* to a Hard invariant in
this file when it (a) recurs across machines/agents/sessions despite being
documented, (b) silently corrupts state, or (c) the workaround is non-obvious
enough that "remember to do X" isn't safe. When graduating, leave the
`pitfalls/<slug>.md` as historical record and link to it from the new
invariant.

`pitfalls/` is excluded from chezmoi (see .chezmoiignore.tmpl) and
**not** auto-redacted; review for secrets before committing.
<!-- project-knowledge-harness:agent-guidance --> (end)
