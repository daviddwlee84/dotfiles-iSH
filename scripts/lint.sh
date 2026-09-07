#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
shellcheck -x -S warning -s sh bootstrap.sh scripts/core.sh scripts/manage.sh scripts/lint.sh scripts/ci-tools.sh home/modify_dot_profile home/dot_config/dotfiles-lite/*.sh
for file in bootstrap.sh scripts/core.sh scripts/manage.sh scripts/lint.sh home/modify_dot_profile home/dot_config/dotfiles-lite/*.sh; do
    sh -n "$file"
done
