# deck-tools

Deck tools for managing dosbox stuff and also a shader cache tool.

---

## Quick Install

No cloning required. Paste one command into a terminal and the rest is automatic.

### Option A — Steam Deck Konsole (Desktop Mode)

Switch to Desktop Mode, open **Konsole**, and run:

```bash
bash <(curl -sSL https://raw.githubusercontent.com/jaydarkseed757/deck-tools/main/install.sh)
```

### Option B — SSH from your laptop or desktop *(the fun way)*

Set up your Steam Deck without ever touching its keyboard — run the installer
remotely from your couch, your desk, or anywhere on the same network.

**1. Enable SSH on your Steam Deck**

In Gaming Mode:  
`Steam button → Settings → System → scroll to "Network" → Enable SSH`

**2. Set a password** (SSH requires one; Steam Deck ships without one by default)

Open Konsole in Desktop Mode and run:
```bash
passwd
```

**3. Find your Deck's IP address**

In Gaming Mode:  
`Steam button → Settings → System → IP Address`

Or in Konsole:
```bash
ip -4 addr show wlan0 | grep inet
```

**4. Run the installer from your other machine**

```bash
ssh deck@<DECK-IP> 'bash <(curl -sSL https://raw.githubusercontent.com/jaydarkseed757/deck-tools/main/install.sh)'
```

Replace `<DECK-IP>` with the address from step 3. That's it — the installer
runs on the Deck, you watch the output on your machine.

### Option C — Manual (git clone)

```bash
git clone https://github.com/jaydarkseed757/deck-tools
cd deck-tools/dos-workstation
bash setup.sh
```

### Updating

Re-run the same curl command. `install.sh` always downloads the latest version
before running setup, so it's safe to re-run at any time.

### Flags

Both the curl installer and `setup.sh` accept:

| Flag | Effect |
|------|--------|
| `--dry-run` | Print every action without making any changes |
| `--skip-flatpak` | Skip DOSBox Staging / RetroArch install (already installed) |

```bash
# Preview what would happen, nothing is changed
bash <(curl -sSL https://raw.githubusercontent.com/jaydarkseed757/deck-tools/main/install.sh) --dry-run
```

---

## DOS Workstation (`dos-workstation/`)

Turns your Steam Deck into a portable DOS development machine running DOSBox Staging,
RetroArch, QBASIC 1.1, and GW-BASIC.

`setup.sh` does all of this automatically:

- Creates `~/DOSGames/` with the full workspace tree
- Installs **DOSBox Staging** and **RetroArch** via Flatpak (user install, no `sudo`)
- Deploys Steam Deck-optimised DOSBox configs
- Installs launcher scripts to `~/.local/bin/`
- Creates `.desktop` shortcuts for Desktop Mode

### Workspace layout

```
~/DOSGames/
├── GAMES/
│   ├── DOOM/
│   ├── DUKE3D/
│   └── WOLF3D/
├── QBASIC/        ← copy QBASIC.EXE + QBASIC.HLP here
├── GWBASIC/       ← copy GWBASIC.EXE here
├── PROJECTS/
│   ├── BLACKJACK/
│   ├── HANGMAN/
│   └── DEMOS/
└── UTILS/
```

### Deploy a game — `dos-game-deploy.sh`

```bash
bash dos-workstation/dos-game-deploy.sh <game-name> [source-directory]
```

Point it at any unzipped DOS game folder and it handles everything:

- Copies the game to `~/DOSGames/GAMES/<GAME>/`
- Detects the main `.EXE` (by name match, known-game table, or first EXE found)
- Generates a per-game DOSBox Staging config (`cycles = max`, SB16, `svga_s3`)
- Writes a launcher script to `~/.local/bin/launch_<game>.sh`
- Creates a `.desktop` shortcut
- Prints numbered, step-by-step instructions for adding it to Gaming Mode

```bash
# Game folder is in the current directory
bash dos-workstation/dos-game-deploy.sh quake

# Explicit source path
bash dos-workstation/dos-game-deploy.sh doom ~/Downloads/doom
bash dos-workstation/dos-game-deploy.sh wolf3d /run/media/mysdcard/wolf3d
```

Known games with automatic EXE detection: DOOM, DOOM2, Duke3D, Wolf3D, Quake,
Heretic, Hexen, Descent, Descent2, Tyrian, X-COM, Warcraft, Warcraft 2, and more.

### Launchers

| Script | Description |
|--------|-------------|
| `launch_dos.sh` | DOSBox Staging with the full DOS workspace |
| `launch_qbasic.sh [file.bas]` | Boots straight into the QBASIC IDE; optionally opens a `.BAS` file |

Add either script as a **non-Steam Game** in Steam Desktop Mode
(`Games → Add a Non-Steam Game`) to make it appear in Gaming Mode.

### Steam Deck controls (recommended Steam Input layout)

| Control | DOS action |
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
Key settings: `machine = svga_s3` (best VGA / SCREEN 13 support), `aspect = true`
(4:3 letterboxed on the 16:10 Steam Deck screen), `glshader = sharp`.

### Required files (not bundled)

QBASIC and GW-BASIC are not included; obtain them legally from:
- MS-DOS 5 or 6 installation disks / images
- The [FreeDOS](https://www.freedos.org) project (compatible open-source replacements)

---

## shader_cache_report.sh

Shows shader cache and Proton compatdata usage on your Steam Deck — internal storage
and SD card — with game name resolution from installed app manifests.

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

---

https://github.com/jaydarkseed757/deck-tools
