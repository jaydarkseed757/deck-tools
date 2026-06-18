#!/usr/bin/env bash
# dos-game-deploy.sh — Deploy a DOS game for Steam Deck Gaming Mode
#
# Usage:
#   bash dos-game-deploy.sh <game-name> [source-directory]
#
# Examples:
#   bash dos-game-deploy.sh quake
#   bash dos-game-deploy.sh doom  ~/Downloads/doom
#   bash dos-game-deploy.sh wolf3d /mnt/sdcard/wolf3d
#
# Assumptions:
#   • Source folder contains the game files, including a .EXE launcher.
#   • The EXE name ideally matches the game name (e.g. quake → quake.exe).
#   • setup.sh has already been run (DOSBox Staging installed, configs deployed).
#
# What this script does:
#   1. Locates and validates the source game folder.
#   2. Detects the main executable.
#   3. Copies the game to ~/DOSGames/GAMES/<GAME>/.
#   4. Generates a per-game DOSBox Staging config.
#   5. Generates a launcher script in ~/.local/bin/.
#   6. Creates a .desktop shortcut for Desktop Mode.
#   7. Prints step-by-step instructions for Gaming Mode.

set -euo pipefail

# ─── Colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERR ]${NC}  $*" >&2; }
header()  { echo -e "\n${BOLD}${BLUE}── $* ──${NC}"; }
step()    { echo -e "  ${CYAN}→${NC} $*"; }
blank()   { echo ""; }

# ─── Argument parsing ─────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 <game-name> [source-directory]"
    echo ""
    echo "  game-name         Folder/game name (e.g. quake, doom, wolf3d)"
    echo "  source-directory  Path to the unzipped game folder (default: ./<game-name>)"
    echo ""
    echo "Examples:"
    echo "  $0 quake"
    echo "  $0 doom  ~/Downloads/doom"
}

if [[ $# -lt 1 ]]; then
    error "A game name is required."
    blank
    usage
    exit 1
fi

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    usage
    exit 0
fi

GAME_RAW="$1"
GAME_LOWER="${GAME_RAW,,}"           # lowercase  →  quake
GAME_UPPER="${GAME_RAW^^}"           # uppercase  →  QUAKE
GAME_TITLE="$(tr '[:lower:]' '[:upper:]' <<< "${GAME_RAW:0:1}")${GAME_RAW:1}"  # Title-case

# ─── Locate source directory ──────────────────────────────────────────────────
header "Locating Source Folder"

# Search order:
#   1. Explicit path supplied as $2
#   2. <current dir>/<game-name>  (user ran script from parent of game folder)
#   3. <current dir>              (user ran script from inside the game folder)
#   4. ~/Downloads/<game-name>
#   5. ~/Desktop/<game-name>

CANDIDATE_PATHS=()
[[ $# -ge 2 ]] && CANDIDATE_PATHS+=("$2")
CANDIDATE_PATHS+=(
    "$(pwd)/${GAME_LOWER}"
    "$(pwd)/${GAME_UPPER}"
    "$(pwd)"
    "${HOME}/Downloads/${GAME_LOWER}"
    "${HOME}/Downloads/${GAME_UPPER}"
    "${HOME}/Desktop/${GAME_LOWER}"
    "${HOME}/Desktop/${GAME_UPPER}"
)

SRC_DIR=""
for candidate in "${CANDIDATE_PATHS[@]}"; do
    # A valid source dir must exist and contain at least one .exe
    # (case-insensitive). -quit stops find at the first match.
    [[ -d "$candidate" ]] || continue
    if find "$candidate" -maxdepth 1 -iname "*.exe" -print -quit 2>/dev/null | grep -q .; then
        SRC_DIR="$candidate"
        break
    fi
done

if [[ -z "$SRC_DIR" ]]; then
    error "Could not find the game folder for '${GAME_RAW}'."
    blank
    echo "Searched:"
    for c in "${CANDIDATE_PATHS[@]}"; do echo "  $c"; done
    blank
    echo "Make sure the game is unzipped to a folder named '${GAME_LOWER}' then run:"
    echo "  $0 ${GAME_LOWER} /path/to/${GAME_LOWER}"
    exit 1
fi

success "Found source: ${SRC_DIR}"

# ─── Detect main executable ───────────────────────────────────────────────────
header "Detecting Main Executable"

# Well-known game → executable overrides
declare -A KNOWN_EXES=(
    [doom]="DOOM.EXE"
    [doom2]="DOOM2.EXE"
    [doomu]="DOOM.EXE"
    [duke3d]="DUKE3D.EXE"
    [duke]="DUKE3D.EXE"
    [wolf3d]="WOLF3D.EXE"
    [wolfenstein]="WOLF3D.EXE"
    [quake]="QUAKE.EXE"
    [heretic]="HERETIC.EXE"
    [hexen]="HEXEN.EXE"
    [hexen2]="GLHEXEN2.EXE"
    [descent]="DESCENT.EXE"
    [descent2]="DESCENT2.EXE"
    [blake]="BLAKE.EXE"
    [commander_keen]="CK4.EXE"
    [keen]="KEEN4E.EXE"
    [raiden]="RAIDEN.EXE"
    [tyrian]="TYRIAN.EXE"
    [xcom]="XCOM.EXE"
    [terror]="TERROR.EXE"
    [warcraft]="WAR.EXE"
    [warcraft2]="WAR2.EXE"
    [diablo]="DIABLO.EXE"
    [stunts]="STUNTS.EXE"
    [theme_hospital]="HOSPITAL.EXE"
    [simcity]="SC2000.EXE"
)

EXE_NAME=""

# 1. Check known overrides
if [[ -v KNOWN_EXES[$GAME_LOWER] ]]; then
    OVERRIDE="${KNOWN_EXES[$GAME_LOWER]}"
    MATCH="$(find "$SRC_DIR" -maxdepth 1 -iname "$OVERRIDE" -print -quit 2>/dev/null || true)"
    if [[ -n "$MATCH" ]]; then
        EXE_NAME="$(basename "$MATCH")"
        info "Matched known game EXE: ${EXE_NAME}"
    fi
fi

# 2. Try <gamename>.exe (case-insensitive)
if [[ -z "$EXE_NAME" ]]; then
    MATCH="$(find "$SRC_DIR" -maxdepth 1 -iname "${GAME_LOWER}.exe" -print -quit 2>/dev/null || true)"
    if [[ -n "$MATCH" ]]; then
        EXE_NAME="$(basename "$MATCH")"
        info "Matched by game name: ${EXE_NAME}"
    fi
fi

# 3. List all .exe files and pick the most likely one
if [[ -z "$EXE_NAME" ]]; then
    mapfile -t ALL_EXES < <(find "$SRC_DIR" -maxdepth 1 -iname "*.exe" -printf "%f\n" 2>/dev/null | sort)

    if [[ ${#ALL_EXES[@]} -eq 0 ]]; then
        error "No .EXE files found in ${SRC_DIR}"
        echo "Ensure the game is fully extracted and contains an .exe launcher."
        exit 1
    elif [[ ${#ALL_EXES[@]} -eq 1 ]]; then
        EXE_NAME="${ALL_EXES[0]}"
        info "Only one EXE found: ${EXE_NAME}"
    else
        warn "Multiple .EXE files found — picking the first one."
        warn "Override with: $0 ${GAME_LOWER} <source> (then edit the generated config)"
        echo ""
        echo "  EXEs found in ${SRC_DIR}:"
        for exe in "${ALL_EXES[@]}"; do echo "    $exe"; done
        echo ""
        EXE_NAME="${ALL_EXES[0]}"
        info "Using: ${EXE_NAME}"
    fi
fi

EXE_UPPER="${EXE_NAME^^}"
success "Main executable: ${EXE_UPPER}"

# ─── Paths ────────────────────────────────────────────────────────────────────
DOS_ROOT="${HOME}/DOSGames"
GAMES_DIR="${DOS_ROOT}/GAMES"
GAME_DEST="${GAMES_DIR}/${GAME_UPPER}"

DOSBOX_ID="io.github.dosbox-staging"
DOSBOX_CFG_DIR="${HOME}/.var/app/${DOSBOX_ID}/config/dosbox"
GAME_CFG="${DOSBOX_CFG_DIR}/dosbox-${GAME_LOWER}.conf"

LAUNCHER="${HOME}/.local/bin/launch_${GAME_LOWER}.sh"
DESKTOP="${HOME}/.local/share/applications/dos-${GAME_LOWER}.desktop"

# ─── Deploy game files ────────────────────────────────────────────────────────
header "Deploying Game Files"

mkdir -p "$GAME_DEST"

if [[ "$(realpath "$SRC_DIR")" == "$(realpath "$GAME_DEST")" ]]; then
    success "Game files already at destination — no copy needed"
else
    FILE_COUNT="$(find "$SRC_DIR" -type f | wc -l)"
    info "Copying ${FILE_COUNT} files to ${GAME_DEST} …"
    cp -r "${SRC_DIR}/." "${GAME_DEST}/"
    success "Copied to ${GAME_DEST}"
fi

# ─── Generate DOSBox config ───────────────────────────────────────────────────
header "Generating DOSBox Config"

mkdir -p "$DOSBOX_CFG_DIR"

if [[ -f "$GAME_CFG" ]]; then
    BAK="${GAME_CFG}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$GAME_CFG" "$BAK"
    warn "Existing config backed up → $BAK"
fi

cat > "$GAME_CFG" << EOF
# dosbox-${GAME_LOWER}.conf — DOSBox Staging config for ${GAME_TITLE}
#
# Generated by dos-game-deploy.sh on $(date '+%Y-%m-%d %H:%M:%S')
# Main executable: ${EXE_UPPER}
#
# Tuning tips:
#   cycles = max          Fastest possible (best for late-DOS 3D games)
#   cycles = fixed 50000  Fixed speed (more predictable for older games)
#   cycles = auto         DOSBox auto-tunes per frame

[sdl]
fullscreen             = true
fullresolution         = desktop
output                 = opengl
gl_bilinear_filtering  = false
autolock               = false
waitonerror            = true
priority               = higher,normal
usescancodes           = true

[dosbox]
machine                = svga_s3
memsize                = 16

[render]
frameskip              = 0
aspect                 = true
scaler                 = none
glshader               = sharp

[cpu]
core                   = auto
cputype                = auto
# 'max' is recommended for action games and 3D engines.
cycles                 = max
cycleup                = 10
cycledown              = 20

[mixer]
nosound                = false
rate                   = 44100
blocksize              = 1024
prebuffer              = 25

[midi]
mpu401                 = intelligent
mididevice             = default

[sblaster]
sbtype                 = sb16
sbbase                 = 220
irq                    = 7
dma                    = 1
hdma                   = 5
sbmixer                = true
oplmode                = auto

[gus]
gus                    = false

[speaker]
pcspeaker              = true
pcrate                 = 44100
tandy                  = off
disney                 = false

[joystick]
joysticktype           = auto
timed                  = true

[serial]
serial1                = dummy
serial2                = dummy
serial3                = disabled
serial4                = disabled

[dos]
xms                    = true
ems                    = true
umb                    = true
keyboardlayout         = auto

[ipx]
ipx                    = false

[autoexec]
@echo off
mount C ${HOME}/DOSGames
C:
CD GAMES\\${GAME_UPPER}
${EXE_UPPER}
EOF

success "Config written: ${GAME_CFG}"

# ─── Generate launcher script ─────────────────────────────────────────────────
header "Generating Launcher Script"

mkdir -p "$(dirname "$LAUNCHER")"

cat > "$LAUNCHER" << EOF
#!/usr/bin/env bash
# launch_${GAME_LOWER}.sh — Launch ${GAME_TITLE} via DOSBox Staging
# Generated by dos-game-deploy.sh

DOSBOX_ID="${DOSBOX_ID}"
CFG="${GAME_CFG}"

if ! flatpak list --user 2>/dev/null | grep -q "\$DOSBOX_ID" && \\
   ! flatpak list        2>/dev/null | grep -q "\$DOSBOX_ID"; then
    echo "DOSBox Staging is not installed."
    echo "  flatpak install --user flathub \${DOSBOX_ID}"
    exit 1
fi

exec flatpak run "\$DOSBOX_ID" --conf "\$CFG"
EOF

chmod +x "$LAUNCHER"
success "Launcher written: ${LAUNCHER}"

# ─── Create .desktop shortcut ─────────────────────────────────────────────────
header "Creating Desktop Shortcut"

mkdir -p "$(dirname "$DESKTOP")"

cat > "$DESKTOP" << EOF
[Desktop Entry]
Name=${GAME_TITLE}
Comment=Play ${GAME_TITLE} (DOS) via DOSBox Staging
Exec=${LAUNCHER}
Icon=io.github.dosbox-staging
Terminal=false
Type=Application
Categories=Game;Emulator;
StartupNotify=false
EOF

success "Desktop entry written: ${DESKTOP}"

# ─── Steam Gaming Mode instructions ───────────────────────────────────────────
header "How to Launch ${GAME_TITLE} from Gaming Mode"

blank
echo -e "${BOLD}Step 1 — Switch to Desktop Mode${NC}"
echo "  Press the Steam button → Power → Switch to Desktop"
blank
echo -e "${BOLD}Step 2 — Add as a Non-Steam Game${NC}"
echo "  Open Steam (taskbar icon) → Games → Add a Non-Steam Game to My Library"
echo "  Click 'Browse' and navigate to:"
echo ""
echo -e "    ${CYAN}${LAUNCHER}${NC}"
echo ""
echo "  Select it and click 'Add Selected Programs'."
blank
echo -e "${BOLD}Step 3 — Set the shortcut name (optional)${NC}"
echo "  In Steam Library, right-click the new entry → Properties"
echo "  Change the name to: ${GAME_TITLE}"
blank
echo -e "${BOLD}Step 4 — Configure Steam Input${NC}"
echo "  In the same Properties window → Controller → 'Edit Layout'"
echo "  Apply these mappings:"
echo ""
echo "    Left Trackpad    →  Mouse"
echo "    Right Stick      →  Mouse"
echo "    Left  Trigger    →  Left Mouse Click"
echo "    Right Trigger    →  Right Mouse Click"
echo "    A                →  Enter / Confirm"
echo "    B                →  Escape"
echo "    Start            →  Escape  (pause/menu)"
echo "    Steam + X        →  On-screen keyboard"
echo ""
echo "  Save the layout.  You can also browse Community Layouts"
echo "  for 'DOSBox Staging' — there are pre-made Steam Deck layouts."
blank
echo -e "${BOLD}Step 5 — Return to Gaming Mode${NC}"
echo "  Double-click 'Return to Gaming Mode' on the Desktop"
echo "  or press Steam button → Power → Switch to Gaming Mode"
blank
echo -e "${BOLD}Step 6 — Launch${NC}"
echo "  In Gaming Mode → Library → scroll to '${GAME_TITLE}' → press A to launch"
blank
echo -e "${BOLD}Tip — Tune CPU speed if needed${NC}"
echo "  If the game runs too fast or too slow, edit:"
echo -e "  ${CYAN}${GAME_CFG}${NC}"
echo "  Change the 'cycles' line:"
echo "    cycles = max            # full speed  (3D games: DOOM, Quake)"
echo "    cycles = fixed 25000    # ~486 DX2-66 (strategy, early games)"
echo "    cycles = fixed 10000    # ~386 DX-33  (older platformers)"
blank
echo -e "${GREEN}${BOLD}${GAME_TITLE} is ready!${NC}  Enjoy your game."
blank
