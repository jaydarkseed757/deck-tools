# deck-tools
Steam Deck utilities — shader cache management and a DOS retro-computing workstation.

---

## DOS Workstation (`dos-workstation/`)

Turns your Steam Deck into a portable DOS development machine with DOSBox Staging,
RetroArch/DOSBox Pure, QBASIC 1.1, and GW-BASIC.

### Quick start

```bash
cd dos-workstation
bash setup.sh
```

That single command:
- Creates `~/DOSGames/` with the full workspace tree
- Installs **DOSBox Staging** and **RetroArch** via Flatpak (user install, no `sudo`)
- Deploys optimised DOSBox configs for the Steam Deck display
- Installs launcher scripts to `~/.local/bin/`
- Creates `.desktop` shortcuts for Desktop Mode

Run `bash setup.sh --help` for options (`--skip-flatpak`, `--dry-run`).

### Workspace layout

```
~/DOSGames/
├── GAMES/
│   ├── DOOM/
│   ├── DUKE3D/
│   └── WOLF3D/
├── QBASIC/        ← place QBASIC.EXE + QBASIC.HLP here
├── GWBASIC/       ← place GWBASIC.EXE here
├── PROJECTS/
│   ├── BLACKJACK/
│   ├── HANGMAN/
│   └── DEMOS/
└── UTILS/
```

### Deploy a game — `dos-game-deploy.sh`

```bash
bash dos-game-deploy.sh <game-name> [source-directory]
```

Point it at any unzipped DOS game folder and it handles everything:
- Copies the game to `~/DOSGames/GAMES/<GAME>/`
- Detects the main `.EXE` (by name match, known-game table, or first EXE found)
- Generates a per-game DOSBox config (`cycles = max`, SB16, `svga_s3`)
- Writes a launcher script to `~/.local/bin/launch_<game>.sh`
- Creates a `.desktop` shortcut
- Prints numbered, step-by-step instructions for adding it to Gaming Mode

```bash
# Game folder is in the current directory
bash dos-game-deploy.sh quake

# Explicit source path
bash dos-game-deploy.sh doom ~/Downloads/doom
bash dos-game-deploy.sh wolf3d /run/media/mysdcard/wolf3d
```

Known games with automatic EXE detection: DOOM, DOOM2, Duke3D, Wolf3D, Quake,
Heretic, Hexen, Descent, Descent2, Tyrian, X-COM, Warcraft, Warcraft 2, and more.

After running the script, follow the printed steps — they walk you through
Desktop Mode → Add Non-Steam Game → Steam Input → Gaming Mode launch.

### Launchers (general)

| Script | Description |
|--------|-------------|
| `launch_dos.sh` | DOSBox Staging with the full DOS workspace |
| `launch_qbasic.sh [file.bas]` | Boots straight into QBASIC IDE; optionally opens a `.BAS` file |

Add either script as a **non-Steam game** in Steam Desktop Mode (`Games → Add a Non-Steam
Game`) so they appear in Gaming Mode. Then apply the recommended Steam Input layout below.

### Steam Deck controls (recommended Steam Input layout)

| Control | DOS Action |
|---------|-----------|
| Left Trackpad | Mouse pointer |
| Right Stick | Mouse pointer |
| Left Trigger | Left mouse click |
| Right Trigger | Right mouse click |
| A | Enter |
| B | Escape |
| Steam + X | On-screen keyboard |

### DOSBox configs

| File | Used for |
|------|---------|
| `configs/dosbox-staging.conf` | General DOS workspace — `cycles = auto`, fullscreen |
| `configs/dosbox-qbasic.conf` | QBASIC IDE — `cycles = fixed 25000`, auto-launches QBASIC |

Both configs are deployed to
`~/.var/app/io.github.dosbox-staging/config/dosbox/` by `setup.sh`.
Key settings: `machine = svga_s3` (best VGA/SCREEN 13 support), `aspect = true`
(4:3 letterboxed on the 16:10 Steam Deck screen), `glshader = sharp`.

### Required files (not bundled)

QBASIC and GW-BASIC are not included; obtain them legally from:
- MS-DOS 5 or 6 installation disks / images
- The [FreeDOS](https://www.freedos.org) project (compatible replacements)

---

## shader_cache_report.sh

Shows shader cache and Proton compatdata usage on your Steam Deck — internal storage and SD card — with game name resolution from installed app manifests.

### Usage

```
./shader_cache_report.sh [OPTIONS]
```

### Options

| Option | Description |
|--------|-------------|
| `--clean` | Scan for orphaned cache entries (no matching installed game) and interactively offer to delete them |
| `--csv` | Export the full report as CSV (`type,location,appid,name,size_bytes`) — suitable for piping or saving to a file |
| `--game <name>` | Look up cache usage for a specific game by name (partial, case-insensitive match) |
| `--json` | Export the full report as JSON — suitable for piping or processing with other tools |
| `--nosd` | Skip SD card storage scan |
| `--top <N>` | Show top N entries per section (default: 10) |
| `--warn-at <size>` | Print a warning if total cache usage exceeds the given size (e.g. `20G`, `500M`, `1.5T`) |
| `--help` | Show usage information |

### Examples

```bash
# Full report
./shader_cache_report.sh

# Skip SD card
./shader_cache_report.sh --nosd

# Show top 5 entries per section
./shader_cache_report.sh --top 5

# Look up a specific game
./shader_cache_report.sh --game "Elden Ring"

# Find and clean up orphaned cache entries
./shader_cache_report.sh --clean

# Warn if total cache exceeds 20GB
./shader_cache_report.sh --warn-at 20G

# Export to CSV
./shader_cache_report.sh --csv > cache.csv

# Export to JSON
./shader_cache_report.sh --json > cache.json

# Combine flags
./shader_cache_report.sh --nosd --csv > internal_only.csv
```

### Source

https://github.com/jaydarkseed757/deck-tools
