#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
shellcheck -x -S warning -s sh bootstrap.sh scripts/core.sh scripts/manage.sh scripts/update.sh scripts/lint.sh scripts/ci-tools.sh home/modify_dot_profile home/modify_dot_bashrc home/dot_config/dotfiles-lite/*.sh
for file in bootstrap.sh scripts/core.sh scripts/manage.sh scripts/update.sh scripts/lint.sh home/modify_dot_profile home/modify_dot_bashrc home/dot_config/dotfiles-lite/*.sh; do
    sh -n "$file"
done
if [ -f scripts/sshd.sh ]; then
    shellcheck -x -S warning -s sh scripts/sshd.sh scripts/ish-probe.sh scripts/build-hako.sh scripts/build-herdr-ish.sh config/sshd/dotfiles-sshd
    sh -n scripts/sshd.sh
    sh -n scripts/ish-probe.sh
    sh -n scripts/build-hako.sh
    sh -n scripts/build-herdr-ish.sh
    sh -n config/sshd/dotfiles-sshd
    shellcheck -S warning -s sh experiments/generate-herdr-bindings.sh
    sh -n experiments/generate-herdr-bindings.sh
fi
if [ -f scripts/finder.sh ]; then
    shellcheck -x -S warning -s sh scripts/finder.sh scripts/finder-mount.sh config/finder/dotfiles-finder
    sh -n scripts/finder.sh
    sh -n scripts/finder-mount.sh
    sh -n config/finder/dotfiles-finder
fi
