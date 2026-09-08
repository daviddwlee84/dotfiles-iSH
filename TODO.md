# TODO

Long-term backlog for dotfiles-iSH. See AGENTS.md
for the maintenance workflow that agents should follow.

> **For agents**: when the user surfaces an idea explicitly **not** being
> implemented this session (signals: "maybe later", "nice to have",
> "工程量太大需要再評估", "先記下來"), add it here with priority + effort tags.
> Do not create new `ROADMAP.md` / `IDEAS.md` / `BACKLOG.md` files —
> `TODO.md` is the single backlog index. Long-form research goes in
> [`backlog/<slug>.md`](backlog/).

<!-- Use the exact section order: P1, P2, P3, P?, Done.
     The bundled scripts/todo-kanban.sh validator only inspects top-level
     `- [ ]` and `- ✅` items inside these sections. Prose paragraphs,
     blockquotes, indented sub-bullets, HTML comments, and `---` rules are
     ignored — feel free to add inline guidance like this without breaking
     machine readability. -->

## P1

Likely next batch — items you'd reach for if you sat down to work today.


## P2

Worth doing, no rush.


## P3

Someday / nice-to-have.


## P?

Needs a spike before committing to a real priority. Tag as `[?/Effort]`.
- [ ] **[?/M] Validate chezmoi on an actual iSH device** — iSH 1.3.2 stalled over five minutes during the 2.72.1 probe; timeout is hardened, but runtime acceptance remains pending. Retain explicit sh recovery. → [research](backlog/validate-chezmoi-on-an-actual-ish-device.md)
- [ ] **[?/L] Validate local agents and Herdr on iSH** — SSH test access and bounded probes are implemented; complete authenticated device workflows before enabling local-agent installers. → [research](backlog/validate-local-agents-and-herdr-on-ish.md)


## Done

Recently shipped. When implementing an active item, in the same commit run:

```
scripts/promote-todo.sh --title "<substring>" --summary "<one-line shipped summary>"
```

This moves the entry here using the dated `Done` syntax and re-validates.


<!-- Prune older entries into CHANGELOG.md once prior-year items appear here
     or this section grows past ~20 entries. -->
