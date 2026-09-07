set shell := ["sh", "-eu", "-c"]
root := justfile_directory()
default:
    @just --list
apply *ARGS:
    sh "{{root}}/bootstrap.sh" {{ARGS}}
diff:
    sh "{{root}}/bootstrap.sh" --dry-run --config-only
doctor:
    sh "{{root}}/bootstrap.sh" --doctor
lint:
    sh scripts/lint.sh
test:
    bats tests
docs-build:
    uv run --no-project --with 'mkdocs<2' --with mkdocs-material --with mkdocs-static-i18n mkdocs build --strict
check: lint test docs-build
