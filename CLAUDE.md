# deck-tools — Claude Code Guide

Deck tools for managing DOSBox stuff and also a shader cache tool, targeting the Steam Deck (SteamOS).

## Repo layout

```
install.sh                          One-command curl installer (bootstrap only)
dos-workstation/
  setup.sh                          Main installer — Flatpak, workspace, configs, launchers
  dos-game-deploy.sh                Deploy a single DOS game; fetch from archive.org or local path
  dos-game-list.sh                  List all deployed games and their artifact status
  dos-game-remove.sh                Remove a deployed game and all its artifacts
  steam_shortcuts.py                Python helper — read/write Steam's binary shortcuts.vdf
  repos.txt                         Curated shareware game list used by --browse
  configs/
    dosbox-staging.conf             General DOS workspace config (uses __HOME__ placeholder)
    dosbox-qbasic.conf              QBASIC-specific config (cycles = fixed 25000, auto-launches IDE)
  launchers/
    launch_dos.sh                   Open the DOS workspace in DOSBox Staging
    launch_qbasic.sh                Launch the QBASIC 1.1 IDE (optional .BAS file arg)
shader_cache_report.sh              Steam shader cache usage report
```

## Key conventions

- `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` — every script that references sibling files must define this; `dos-game-deploy.sh` needs it to locate `repos.txt`.
- `__HOME__` placeholder in config templates — replaced with `sed "s|__HOME__|${HOME}|g"` at deploy time by `setup.sh`.
- Python3 for JSON parsing — avoids `jq` dependency (python3 is always present on SteamOS). Always use a **quoted heredoc** (`<< 'PYEOF'`) to prevent bash expanding `$` inside Python source; write JSON to a temp file and pass its path via `sys.argv[1]`.
- `flatpak list --user` then `flatpak list` — check both user and system installs; grep for the app ID.
- `cycles = max` for action/3D games; `cycles = fixed 25000` for QBASIC and older games.
- DOSBox Staging Flatpak ID: `io.github.dosbox-staging`; config dir: `~/.var/app/io.github.dosbox-staging/config/dosbox/`.
- `launch_qbasic.sh` with a `.BAS` file argument must use `dosbox-staging.conf` (not `dosbox-qbasic.conf`) — the QBASIC config's autoexec blocks on the IDE, so `-c` commands never run.

## Development

Feature branch: `claude/steam-deck-dos-workstation-0gngxz`
Merge to `main` when complete.

Syntax-check scripts before committing:
```bash
bash -n dos-workstation/dos-game-deploy.sh
bash -n dos-workstation/setup.sh
```

## Key conventions (additions)

- `steam_shortcuts.py` — call via `python3 "${SCRIPT_DIR}/steam_shortcuts.py" add/list/remove`. Uses raw byte preservation when reading existing entries (no data loss). Writes atomically via `.tmp` + `os.replace`. Searches three Steam userdata path patterns to handle Deck vs desktop Steam installs.
- `dos-game-deploy.sh --steam` — calls `steam_shortcuts.py add` after the launcher is written; silently skips with a warning if the Python helper is missing or Steam userdata doesn't exist yet.
- `dos-game-remove.sh` — always confirms before destructive deletion. Calls `steam_shortcuts.py remove` if available.

## Outstanding TODOs

- **Verify archive.org item IDs in `repos.txt`** — only Quake (`msdos_Quake106_shareware`), DOOM (`doom_dos`), and Duke3D (`DUKE3D_DOS`) have been confirmed. The following need a human to open the URL and confirm a ZIP is available:
  - `doom2demo` (DOOM II Demo)
  - `heretic-shareware` (Heretic Shareware)
  - `hexen-demo` (Hexen Demo)
  - `quake-ii-shareware` (Quake II Shareware)
  - `keen4e` (Commander Keen 4 Shareware)
  - `wolf3d-shareware` (Wolfenstein 3D Shareware)
