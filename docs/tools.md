# Tools and support

Default: `git openssh-client tmux nano vim curl ca-certificates` from the current
Alpine repositories. `--with dev` adds `jq less rsync python3` from the same feeds.
Python's version is whatever that branch supports; modern wheels/LSPs are not promised.

Use ash with the small profile fragment. Full Unix zsh, mise, Ansible, Node-based
agents, Herdr and SpecStory are not part of local support. The locked chezmoi i386
binary exists, but `--manager chezmoi` remains experimental on the iSH emulator.
No source builds or Alpine branch migration are attempted.

`ovault [SUBDIR]` opens the iOS Files picker as needed and enters the vault.
`OBSIDIAN_MNT` defaults to `/mnt/dq/Obsidian`; override it in local.sh.
`ovsync [REPO] [MESSAGE]` explicitly stages all edits, commits, rebases and pushes.
It is never run by bootstrap. Configure Git identity and SSH keys yourself first.
The mount check is an empty-directory heuristic: an empty mounted folder can show
the picker again. App restart requires remounting. safe.directory is added only
for the exact selected Git directory, never a wildcard.

Existing inline `ish-bootstrap (obsidian)` helpers are retained. The new fragment
loads its helpers only when `ovault` is absent. To adopt new helper code, review
and manually remove the old marked block while retaining any custom mount path.
The SSH seed preserves existing configuration; the tmux seed uses Ctrl+b then
1..9, with extended keys and mouse omitted. Existing tmux config is left intact.

For agents, SSH to your Unix host, attach Herdr there, and launch
`specstory run codex` (or another installed agent) in the remote project directory.
The session and history live on that host. See [iOS terminals](ios-terminals.md).
