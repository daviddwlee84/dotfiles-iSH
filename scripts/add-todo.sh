#!/bin/sh
set -eu
exec "$(dirname "$0")/../.agents/skills/project-knowledge-harness/scripts/$(basename "$0")" "$@"
