#!/usr/bin/env bash
# Install the tracked Pi Coding Agent configuration as real files.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
TARGET_DIR="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
BACKUP_DIR="${PI_CONFIG_BACKUP_DIR:-$HOME/.pi-config-backup/$(date +%Y%m%d-%H%M%S)}"
INSTALL_PACKAGES=true

usage() {
    cat <<USAGE
Usage: ./pi/install.sh [options]

Copies the tracked Pi configuration into:
  $TARGET_DIR

Options:
  --skip-packages  Copy configuration files without running npm ci
  --help           Show this help

Tracked configuration files are copied and never symlinked. npm may create
its normal executable shims under the generated node_modules directory.
Existing symlinked configuration paths are moved to:
  $BACKUP_DIR
USAGE
}

backup_path() {
    local target="$1"
    local relative backup_target

    if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        return
    fi

    relative="${target#$HOME/}"
    if [ "$relative" = "$target" ]; then
        relative="absolute${target}"
    fi

    backup_target="$BACKUP_DIR/$relative"
    mkdir -p "$(dirname "$backup_target")"
    mv "$target" "$backup_target"
    printf 'Backed up %s to %s\n' "$target" "$backup_target"
}

# Backs up a file in place, keeping the original at its target, so a merge
# can be retried after inspecting the backup.
backup_path_copy() {
    local target="$1"
    local relative backup_target

    if [ ! -f "$target" ]; then
        return
    fi

    relative="${target#$HOME/}"
    if [ "$relative" = "$target" ]; then
        relative="absolute${target}"
    fi

    backup_target="$BACKUP_DIR/$relative"
    mkdir -p "$(dirname "$backup_target")"
    cp -p "$target" "$backup_target"
    printf 'Backed up %s to %s\n' "$target" "$backup_target"
}

copy_file() {
    local source="$1"
    local destination="$2"

    mkdir -p "$(dirname "$destination")"

    if [ -L "$destination" ] || { [ -e "$destination" ] && [ ! -f "$destination" ]; }; then
        backup_path "$destination"
    fi

    if [ -f "$destination" ] && cmp -s "$source" "$destination"; then
        printf 'Unchanged %s\n' "$destination"
        return
    fi

    # -L dereferences source symlinks so the installed result is a real file.
    cp -fL "$source" "$destination"
    printf 'Copied %s\n' "$destination"
}

copy_directory() {
    local source="$1"
    local destination="$2"

    if [ -L "$destination" ] || { [ -e "$destination" ] && [ ! -d "$destination" ]; }; then
        backup_path "$destination"
    fi

    mkdir -p "$destination"
    # -L dereferences source symlinks so the installed result contains copies.
    cp -R -L "$source/." "$destination/"
    printf 'Copied %s\n' "$destination"
}

# Fills in keys missing from an existing local settings.json with the repo's
# values. Local values always win on conflict (deep merge, local applied last).
merge_pi_settings() {
    local source="$1"
    local destination="$2"
    local tmp

    if ! command -v jq >/dev/null 2>&1; then
        printf 'jq not found; %s kept as is (install jq and re-run to merge repo keys)\n' "$destination" >&2
        return
    fi

    tmp=$(mktemp)
    if ! jq -s '.[0] * .[1]' "$source" "$destination" > "$tmp"; then
        rm -f "$tmp"
        printf '%s -> could not be parsed as JSON; kept as is\n' "$destination" >&2
        return
    fi

    if [ "$(jq -S . "$tmp")" = "$(jq -S . "$destination")" ]; then
        printf 'Unchanged %s (already has all repo keys)\n' "$destination"
        rm -f "$tmp"
        return
    fi

    backup_path_copy "$destination"
    cat "$tmp" > "$destination"
    rm -f "$tmp"
    printf 'Merged %s -> missing repo keys added, local values kept\n' "$destination"
}

# Pi rewrites settings.json itself (/model, /thinking, theme), so it is always
# a local copy, never a symlink, regardless of install mode. New machines are
# seeded from the repo; existing files only gain keys they are missing.
seed_pi_settings() {
    local source="$SCRIPT_DIR/settings.json"
    local destination="$TARGET_DIR/settings.json"

    if [ ! -f "$source" ]; then
        printf 'Missing Pi settings file: %s\n' "$source" >&2
        exit 1
    fi

    if [ -L "$destination" ]; then
        backup_path "$destination"
        cp -fL "$source" "$destination"
        printf 'Seeded %s\n' "$destination"
    elif [ ! -f "$destination" ]; then
        copy_file "$source" "$destination"
    else
        merge_pi_settings "$source" "$destination"
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --skip-packages) INSTALL_PACKAGES=false ;;
        --help) usage; exit 0 ;;
        *)
            printf 'Unknown option: %s\n\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

[ -d "$SCRIPT_DIR/extensions" ] || { printf 'Missing Pi extensions directory: %s\n' "$SCRIPT_DIR/extensions" >&2; exit 1; }
[ -d "$SCRIPT_DIR/themes" ] || { printf 'Missing Pi themes directory: %s\n' "$SCRIPT_DIR/themes" >&2; exit 1; }

# Do not install through a symlinked Pi config root.
if [ -L "$TARGET_DIR" ] || { [ -e "$TARGET_DIR" ] && [ ! -d "$TARGET_DIR" ]; }; then
    backup_path "$TARGET_DIR"
fi
mkdir -p "$TARGET_DIR"

# Retire paths used by earlier versions of this configuration.
for legacy in answer.ts editor.ts effort.ts footer.ts header.ts theme.ts answer thinking; do
    backup_path "$TARGET_DIR/extensions/$legacy"
done

copy_directory "$SCRIPT_DIR/extensions" "$TARGET_DIR/extensions"
copy_directory "$SCRIPT_DIR/themes" "$TARGET_DIR/themes"
seed_pi_settings
copy_file "$SCRIPT_DIR/keybindings.json" "$TARGET_DIR/keybindings.json"
# models-store.json is Pi's own model-catalog cache, rewritten by pi on every
# catalog refresh; it is intentionally not tracked or installed.
copy_file "$SCRIPT_DIR/npm/package.json" "$TARGET_DIR/npm/package.json"
copy_file "$SCRIPT_DIR/npm/package-lock.json" "$TARGET_DIR/npm/package-lock.json"
copy_file "$SCRIPT_DIR/npm/.gitignore" "$TARGET_DIR/npm/.gitignore"

if [ "$INSTALL_PACKAGES" = true ]; then
    if command -v npm >/dev/null 2>&1; then
        printf 'Installing Pi packages...\n'
        (
            cd "$TARGET_DIR/npm"
            npm ci --ignore-scripts --no-audit --no-fund
        )
    else
        printf 'npm was not found; skipped Pi package installation.\n' >&2
    fi
fi

printf '\nPi Coding Agent configuration installed in %s\n' "$TARGET_DIR"
