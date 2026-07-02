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

- `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` — every script that references sibling files must define this.
- `__HOME__` placeholder in config templates — replaced with `sed "s|__HOME__|${HOME}|g"` at deploy time by `setup.sh`.
- Python3 for JSON/VDF parsing — avoids `jq` dependency (python3 is always present on SteamOS). Always use a **quoted heredoc** (`<< 'PYEOF'`) to prevent bash expanding `$` inside Python source; pass file paths via `sys.argv[1]` rather than embedding them in script text.
- `flatpak list --user` then `flatpak list` — check both user and system installs; grep for the app ID.
- `cycles = max` for action/3D games; `cycles = fixed 25000` for QBASIC and older games.
- DOSBox Staging Flatpak ID: `io.github.dosbox-staging`; config dir: `~/.var/app/io.github.dosbox-staging/config/dosbox/`.
- `launch_qbasic.sh` with a `.BAS` file argument must use `dosbox-staging.conf` (not `dosbox-qbasic.conf`) — the QBASIC config's autoexec blocks on the IDE, so `-c` commands never run.
- `steam_shortcuts.py` — call via `python3 "${SCRIPT_DIR}/steam_shortcuts.py" add/list/remove`. Uses raw byte preservation when reading existing entries (no data loss on round-trip), **except** the leading index key: `save_entries` renumbers entries sequentially via `_reindex` — without this, remove-then-add produces duplicate VDF keys and Steam can silently drop a shortcut. Writes atomically via `.tmp` + `os.replace`. The parser raises `ValueError` on any truncated/malformed input (bounded `_skip_cstr`, bounded uint32 advance, non-`\x00` header, unclosed entry) and `load_entries` turns that into a clean `exit 1` — never let a partial parse through, or a later save re-serializes a corrupt file. Searches three Steam userdata path patterns to handle Deck vs desktop Steam installs.
- `dos-game-deploy.sh --steam` — calls `steam_shortcuts.py add` after the launcher is written; silently skips with a warning if the Python helper is missing or Steam userdata doesn't exist yet.
- `dos-game-deploy.sh` EXE detection precedence: `--exe <file>` override → `--interactive` (no auto-run) → known-EXE table → `<gamename>.exe` → alphabetical fallback. `--exe` and `--interactive` are **mutually exclusive** (checked at argument parse). If the resolved EXE is an installer (`INSTALL.EXE`/`SETUP.EXE`/`.BAT`), it auto-switches to interactive mode (skipped when `--exe` was given) and writes a prompt-only autoexec so the installer isn't launched as the "game". After installing, re-deploy with `--exe <GAME.EXE>`. Escape angle brackets in DOS `echo` output as `^<`/`^>`.
- Game names are validated in both `dos-game-deploy.sh` and `dos-game-remove.sh`: reject empty or containing `/` or `..`. The name becomes path components under `~/DOSGames/GAMES` that remove later `rm -rf`s — `'../GAMES'` would resolve to the GAMES dir itself and delete every game. Keep this guard in any new script that turns a game name into a path.
- Deploy source search ends with `~/DOSGames/GAMES/<GAME_UPPER>` as the **last** candidate — this is what makes the post-installer re-deploy (`dos-game-deploy.sh <game> --exe <GAME.EXE>` from any CWD) work. The `realpath` comparison before `cp` prevents self-copy. Fresh local copies (CWD, Downloads, Desktop) intentionally win over the deployed dir.
- archive.org fetch: URL-encode the metadata filename for the download URL (`urllib.parse.quote` via the quoted-heredoc pattern) but keep the raw name for local paths; pick the extraction source dir by **depth** (`find -printf "%d %h\n" | sort -n | head -1 | cut -d' ' -f2-`) — plain alphabetical sort picks e.g. `AData/` over the real game dir when EXEs sit in sibling subdirs.
- `GAME_TITLE` (the Steam shortcut display name) must be derived identically in `dos-game-deploy.sh` and `dos-game-remove.sh` — both from the **raw** argument (`${GAME_RAW:0:1}^^` + `${GAME_RAW:1}`), preserving the case of the tail. Deriving remove's title from `GAME_LOWER` instead orphans the Steam shortcut for any mixed/upper-case name (e.g. `WOLF3D`).
- `dos-game-remove.sh` — always confirms before any destructive deletion (`read ... || REPLY=""` so non-TTY stdin falls through to default-deny instead of aborting under `set -e`). Detects the Steam shortcut **before** the "nothing to remove" early exit, so a shortcut-only orphan is still removable. Matches the existing shortcut with `cut -f1 | grep -Fxqi` (exact, anchored, fixed-string) — never a bare `grep` regex, since archive-derived names contain metacharacters (`.`, `+`, `(`, `)`).
- `setup.sh` installs to `~/.local/bin`: both launchers, all three `dos-game-*.sh` tools, `steam_shortcuts.py`, **and `repos.txt`** — the deploy script resolves `repos.txt` and the Python helper via its own `SCRIPT_DIR`, so anything it needs must ship alongside it. When adding a new sibling dependency to deploy, add it to setup.sh's install steps too.
- `install.sh` does `rm -rf "$DEST"` before extracting (so upstream-deleted files don't linger runnable across upgrades) and uses `curl -sSfL` — keep the `-f`, or HTTP error pages get piped into tar as a cryptic gzip error.
- `launch_qbasic.sh` `.BAS` branch checks `QBASIC.EXE` exists shell-side — the missing-EXE guard in `dosbox-qbasic.conf` doesn't apply there because that branch uses the staging config.
- `shader_cache_report.sh` is considered stable — no need to audit it for bugs.

## Development

Develop on branch `claude/steam-deck-dos-workstation-0gngxz`, merge to `main`.

Syntax-check all scripts before committing:
```bash
bash -n dos-workstation/dos-game-deploy.sh
bash -n dos-workstation/dos-game-list.sh
bash -n dos-workstation/dos-game-remove.sh
bash -n dos-workstation/setup.sh
bash -n dos-workstation/launchers/launch_dos.sh
bash -n dos-workstation/launchers/launch_qbasic.sh
bash -n install.sh
python3 -c "import ast; ast.parse(open('dos-workstation/steam_shortcuts.py').read())"
```

## Outstanding TODOs

- All archive.org item IDs in `repos.txt` have been confirmed.
