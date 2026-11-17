# Pi Coding Agent configuration

This directory contains the portable parts of the Pi Coding Agent configuration imported from `~/.pi/agent`:

- `extensions/` - personal Pi extensions
- `themes/` - custom Pi themes
- `settings.json` - default model, thinking level, theme, and other preferences. Seeds new machines; existing local files only gain missing keys (local values always win)
- `keybindings.json` - keyboard shortcuts
- `npm/` - package manifests for the configured Pi packages

Install the configuration on the current machine directly, or select Pi from the main bootstrap script:

```bash
./install.sh
```

Personal extensions are tracked as source files under `extensions/`. No npm extension packages are currently configured. Packages added with `pi install` must be represented in both the `packages` array in `settings.json` and the npm manifest/lockfile under `npm/`. The installer copies the tracked configuration files and resources into `${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}` rather than symlinking them, then runs `npm ci` to recreate package installs. Use `--skip-packages` to omit that step. npm may create its normal executable shims inside the generated `node_modules/` directory.

`settings.json` follows the same policy as Claude Code settings in the main dotfiles repository: Pi rewrites it itself (`/model`, `/thinking`, theme), so the installer seeds it only on machines that do not have one yet, and otherwise deep-merges it with `jq` (`.[0] * .[1]`), adding repo keys that are missing while local values always win on conflict. A machine-local backup is written to the backup directory before any merge is applied. To reseed, move `settings.json` away and re-run `./install.sh`.

To refresh this snapshot after running `pi install` or `pi remove`, copy `~/.pi/agent/settings.json` and `~/.pi/agent/npm/package.json` back into their matching paths here, review the settings, then regenerate a portable lockfile:

```bash
npm install --prefix npm --package-lock-only --ignore-scripts --no-audit --no-fund
```

Do not copy Pi's managed lockfile verbatim: it may omit peer dependency entries required by `npm ci` on a clean machine.

Machine-specific or sensitive Pi state is intentionally not tracked:

- `auth.json` contains provider credentials; authenticate separately with Pi's `/login` command.
- `sessions/` and `fff/` contain private, machine-local history and indexes.
- `models-store.json` is a cached model catalog that Pi rewrites on every catalog refresh; it is not tracked here and the installer never touches it.
- `trust.json` contains absolute paths and must be recreated on each machine.
- `npm/node_modules/` is generated and platform-specific; the installer recreates it from the lockfile.

The installer backs up extension paths used by earlier versions of this configuration before copying the current layout.
