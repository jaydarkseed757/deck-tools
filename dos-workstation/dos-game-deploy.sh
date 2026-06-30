#!/usr/bin/env bash
# dos-game-deploy.sh — Deploy a DOS game for Steam Deck Gaming Mode
#
# Usage:
#   bash dos-game-deploy.sh <game-name> [source-directory]
#   bash dos-game-deploy.sh --url <archive.org-url> [game-name]
#   bash dos-game-deploy.sh --browse
#
# Examples:
#   bash dos-game-deploy.sh quake
#   bash dos-game-deploy.sh doom  ~/Downloads/doom
#   bash dos-game-deploy.sh wolf3d /mnt/sdcard/wolf3d
#   bash dos-game-deploy.sh --url https://archive.org/details/msdos_Quake106_shareware
#   bash dos-game-deploy.sh --url https://archive.org/details/msdos_Quake106_shareware quake
#   bash dos-game-deploy.sh --browse
#
# What this script does:
#   1. (Optional) Downloads and extracts a game from archive.org.
#   2. Locates and validates the source game folder.
#   3. Detects the main executable.
#   4. Copies the game to ~/DOSGames/GAMES/<GAME>/.
#   5. Generates a per-game DOSBox Staging config.
#   6. Generates a launcher script in ~/.local/bin/.
#   7. Creates a .desktop shortcut for Desktop Mode.
#   8. Prints step-by-step instructions for Gaming Mode.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
    echo "Usage:"
    echo "  $0 <game-name> [source-directory]"
    echo "  $0 --url <archive.org-url> [game-name]"
    echo "  $0 --browse"
    echo ""
    echo "  game-name         Folder/game name (e.g. quake, doom, wolf3d)"
    echo "  source-directory  Path to the unzipped game folder (default: ./<game-name>)"
    echo "  --url             archive.org item URL — downloads and extracts automatically"
    echo "  --browse          Pick from the curated shareware game list interactively"
    echo "  --steam           Auto-add the game to Steam after deploying"
    echo "  --exe <file>      Explicitly set the game EXE (e.g. after running an installer)"
    echo "  --interactive     Deploy files and drop to a DOS prompt instead of auto-running an EXE"
    echo ""
    echo "Examples:"
    echo "  $0 quake"
    echo "  $0 doom  ~/Downloads/doom"
    echo "  $0 --url https://archive.org/details/msdos_Quake106_shareware"
    echo "  $0 --url https://archive.org/details/msdos_Quake106_shareware quake"
    echo "  $0 --browse --steam"
}

IA_URL=""
BROWSE=false
ADD_TO_STEAM=false
EXE_OVERRIDE=""
INTERACTIVE=false
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --url)
            [[ $# -lt 2 ]] && { error "--url requires a URL argument."; exit 1; }
            IA_URL="$2"; shift 2 ;;
        --browse)
            BROWSE=true; shift ;;
        --steam)
            ADD_TO_STEAM=true; shift ;;
        --exe)
            [[ $# -lt 2 ]] && { error "--exe requires a filename argument."; exit 1; }
            EXE_OVERRIDE="$2"; shift 2 ;;
        --interactive)
            INTERACTIVE=true; shift ;;
        --help|-h)
            usage; exit 0 ;;
        --)
            shift; POSITIONAL+=("$@"); break ;;
        -*)
            error "Unknown flag: $1"; blank; usage; exit 1 ;;
        *)
            POSITIONAL+=("$1"); shift ;;
    esac
done
set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}"

if $BROWSE && [[ -n "$IA_URL" ]]; then
    error "--browse and --url are mutually exclusive."
    exit 1
fi

if ! $BROWSE && [[ -z "$IA_URL" && $# -lt 1 ]]; then
    error "A game name, --url, or --browse is required."
    blank
    usage
    exit 1
fi

# ─── Browse curated shareware list ───────────────────────────────────────────
if $BROWSE; then
    REPOS_FILE="${SCRIPT_DIR}/repos.txt"
    if [[ ! -f "$REPOS_FILE" ]]; then
        error "repos.txt not found at ${REPOS_FILE}"
        exit 1
    fi

    GAME_NAMES=(); GAME_URLS=()
    while IFS='|' read -r name url; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        name="${name# }"; name="${name% }"
        url="${url# }";   url="${url% }"
        [[ -z "$name" || -z "$url" ]] && continue
        GAME_NAMES+=("$name"); GAME_URLS+=("$url")
    done < "$REPOS_FILE"

    if [[ ${#GAME_NAMES[@]} -eq 0 ]]; then
        error "repos.txt is empty or has no valid entries."
        exit 1
    fi

    if [[ ! -t 0 ]]; then
        error "--browse requires an interactive terminal."
        exit 1
    fi

    header "Available Shareware Games"
    blank
    for i in "${!GAME_NAMES[@]}"; do
        printf "  %2d)  %s\n" "$((i+1))" "${GAME_NAMES[$i]}"
    done
    blank

    SELECTION=""
    while true; do
        read -rp "Enter number (1-${#GAME_NAMES[@]}) or q to quit: " SELECTION
        [[ "$SELECTION" == "q" ]] && { info "Cancelled."; exit 0; }
        if [[ "$SELECTION" =~ ^[0-9]+$ ]] && \
           (( SELECTION >= 1 && SELECTION <= ${#GAME_NAMES[@]} )); then
            break
        fi
        warn "Invalid selection. Enter a number between 1 and ${#GAME_NAMES[@]}."
    done

    IDX=$(( SELECTION - 1 ))
    IA_URL="${GAME_URLS[$IDX]}"
    info "Selected: ${GAME_NAMES[$IDX]}"
fi

# GAME_RAW may be empty when only --url/--browse is given; the fetch section fills it in.
GAME_RAW="${1:-}"

# ─── Fetch from archive.org ───────────────────────────────────────────────────
SRC_DIR=""

if [[ -n "$IA_URL" ]]; then
    header "Fetching from archive.org"

    if ! command -v unzip &>/dev/null; then
        error "unzip is required for --url downloads."
        echo "  Install it with:  sudo apt install unzip   # or your distro's equivalent"
        exit 1
    fi

    # Create temp directory; cleaned up on exit no matter what
    IA_TMPDIR="$(mktemp -d)"
    trap 'rm -rf "$IA_TMPDIR"' EXIT

    # Parse item ID: strip everything up to and including /details/
    ITEM_ID="${IA_URL##*/details/}"
    ITEM_ID="${ITEM_ID%%\?*}"    # strip query string
    ITEM_ID="${ITEM_ID%%/*}"     # strip any trailing path segments
    info "Item ID: ${ITEM_ID}"

    # Fetch metadata JSON to a file.
    # Writing to a file (instead of capturing in a variable) lets Python read it
    # safely without bash expanding $ characters inside the JSON.
    METADATA_FILE="${IA_TMPDIR}/metadata.json"
    METADATA_URL="https://archive.org/metadata/${ITEM_ID}"
    info "Fetching metadata …"
    curl -sSfL "$METADATA_URL" -o "$METADATA_FILE" || {
        error "Failed to fetch metadata from ${METADATA_URL}"
        echo "  Check the URL and your internet connection."
        exit 1
    }

    if [[ ! -s "$METADATA_FILE" ]]; then
        error "No metadata returned for '${ITEM_ID}'. Check the URL."
        exit 1
    fi

    # Find the best downloadable ZIP.
    # Quoted heredoc (<<'PYEOF') prevents bash from expanding $ inside Python source.
    # METADATA_FILE is passed as sys.argv[1] so it's not embedded in the script text.
    DL_FILE="$(python3 - "$METADATA_FILE" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
files = data.get('files', [])
# Priority 1: format field is exactly "ZIP"
for f in files:
    if f.get('format', '').upper() == 'ZIP':
        print(f['name']); sys.exit(0)
# Priority 2: filename ends in .zip
for f in files:
    if f.get('name', '').lower().endswith('.zip'):
        print(f['name']); sys.exit(0)
sys.exit(1)
PYEOF
    )" || {
        error "No ZIP file found in archive.org item '${ITEM_ID}'."
        echo "Available files:"
        python3 - "$METADATA_FILE" << 'PYEOF'
import json, sys
with open(sys.argv[1]) as fh:
    data = json.load(fh)
for f in data.get('files', []):
    print(f"  {f['name']}  ({f.get('format', '?')})")
PYEOF
        exit 1
    }
    info "Archive file: ${DL_FILE}"

    # Derive GAME_RAW from item ID if user didn't supply a name.
    # ITEM_ID is safe to pass as sys.argv since it comes from a URL path segment.
    if [[ -z "$GAME_RAW" ]]; then
        GAME_RAW="$(python3 - "$ITEM_ID" << 'PYEOF'
import re, sys
s = sys.argv[1]
s = re.sub(r'^(msdos|dos|pc)[_-]', '', s, flags=re.I)
s = re.sub(r'[_-](shareware|demo|full|episode\d*|ep\d*|v?\d[\d._]*).*$', '', s, flags=re.I)
s = re.sub(r'\d+$', '', s)
s = re.split(r'[_\s]', s)[0]
print(s.lower() or 'game')
PYEOF
        )"
        info "Derived game name: ${GAME_RAW}"
    fi

    # Download the ZIP
    DL_URL="https://archive.org/download/${ITEM_ID}/${DL_FILE}"
    info "Downloading ${DL_FILE} …"
    curl -L --progress-bar -o "${IA_TMPDIR}/${DL_FILE}" "$DL_URL" || {
        error "Download failed: ${DL_URL}"
        exit 1
    }
    success "Downloaded: ${DL_FILE}"

    # Extract ZIP
    info "Extracting …"
    mkdir -p "${IA_TMPDIR}/extracted"
    unzip -q "${IA_TMPDIR}/${DL_FILE}" -d "${IA_TMPDIR}/extracted" || {
        error "Extraction failed for ${DL_FILE}"
        exit 1
    }

    # Find the shallowest directory that contains at least one .exe.
    # Sorting alphabetically puts shallower paths (shorter strings) first.
    SRC_DIR="$(find "${IA_TMPDIR}/extracted" -maxdepth 4 -iname "*.exe" \
                   -printf "%h\n" 2>/dev/null | sort | head -1)"

    if [[ -z "$SRC_DIR" ]]; then
        error "No .EXE files found after extracting ${DL_FILE}."
        echo "The archive may not contain a DOS game, or the EXE is nested more than 4 levels deep."
        exit 1
    fi

    success "Game files located at: ${SRC_DIR}"
fi

# ─── Derive name variables (always, after GAME_RAW is finalised) ──────────────
GAME_LOWER="${GAME_RAW,,}"
GAME_UPPER="${GAME_RAW^^}"
GAME_TITLE="$(tr '[:lower:]' '[:upper:]' <<< "${GAME_RAW:0:1}")${GAME_RAW:1}"

# ─── Locate source directory (skipped when --url already set SRC_DIR) ─────────
if [[ -z "$SRC_DIR" ]]; then
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
        echo ""
        echo "Or fetch directly from archive.org:"
        echo "  $0 --url https://archive.org/details/<item-id>"
        exit 1
    fi

    success "Found source: ${SRC_DIR}"
fi

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

if [[ -n "$EXE_OVERRIDE" ]]; then
    EXE_NAME="$EXE_OVERRIDE"
    info "Using specified EXE: ${EXE_NAME^^}"
elif $INTERACTIVE; then
    info "Interactive mode — no EXE auto-run"
else
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
            warn "Override with: $0 ${GAME_LOWER} --exe <EXE.EXE>"
            echo ""
            echo "  EXEs found in ${SRC_DIR}:"
            for exe in "${ALL_EXES[@]}"; do echo "    $exe"; done
            echo ""
            EXE_NAME="${ALL_EXES[0]}"
            info "Using: ${EXE_NAME}"
        fi
    fi

    # Installer auto-detection — skipped when the user explicitly set --exe,
    # since an explicit override means they know which EXE they want.
    if [[ -z "$EXE_OVERRIDE" ]]; then
        INSTALLER_NAMES=("install.exe" "setup.exe" "install.bat" "setup.bat")
        for ins in "${INSTALLER_NAMES[@]}"; do
            if [[ "${EXE_NAME,,}" == "$ins" ]]; then
                warn "Detected installer EXE: ${EXE_NAME^^}"
                warn "Switching to interactive mode — the DOS prompt will open at C:\\GAMES\\${GAME_UPPER}"
                warn "Run the installer there, then re-deploy with:  $0 ${GAME_LOWER} --exe <GAME.EXE>"
                INTERACTIVE=true
                EXE_NAME=""
                break
            fi
        done
    fi
fi

EXE_UPPER="${EXE_NAME^^}"
if $INTERACTIVE; then
    info "Interactive mode — DOS prompt opens at C:\\GAMES\\${GAME_UPPER}"
else
    success "Main executable: ${EXE_UPPER}"
fi

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

# Sanity-check the chosen EXE actually exists in the deployed dir (non-interactive
# only). Checks GAME_DEST, not SRC_DIR, so the post-installer re-deploy workflow
# (--exe naming a file the installer wrote into the destination) still validates.
# A warning, not a failure — the EXE may legitimately be created on first launch.
if ! $INTERACTIVE && \
   ! find "$GAME_DEST" -maxdepth 1 -iname "$EXE_NAME" -print -quit 2>/dev/null | grep -q .; then
    warn "EXE '${EXE_UPPER}' not found in ${GAME_DEST} — the launcher may fail."
    warn "If you meant a different executable, re-run with:  $0 ${GAME_LOWER} --exe <GAME.EXE>"
fi

# ─── Generate DOSBox config ───────────────────────────────────────────────────
header "Generating DOSBox Config"

mkdir -p "$DOSBOX_CFG_DIR"

if [[ -f "$GAME_CFG" ]]; then
    BAK="${GAME_CFG}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$GAME_CFG" "$BAK"
    warn "Existing config backed up → $BAK"
fi

if $INTERACTIVE; then
    CFG_EXE_NOTE="Interactive mode — DOS prompt (run installer, then re-deploy with --exe)"
    AUTOEXEC_FOOTER="echo.
echo  Run the installer, then close DOSBox and re-run:
echo    dos-game-deploy.sh ${GAME_LOWER} --exe ^<GAME.EXE^>
echo."
else
    CFG_EXE_NOTE="Main executable: ${EXE_UPPER}"
    AUTOEXEC_FOOTER="${EXE_UPPER}"
fi

cat > "$GAME_CFG" << EOF
# dosbox-${GAME_LOWER}.conf — DOSBox Staging config for ${GAME_TITLE}
#
# Generated by dos-game-deploy.sh on $(date '+%Y-%m-%d %H:%M:%S')
# ${CFG_EXE_NOTE}
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
${AUTOEXEC_FOOTER}
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

# ─── Add to Steam (optional) ──────────────────────────────────────────────────
if $ADD_TO_STEAM; then
    header "Adding to Steam"
    SHORTCUTS_PY="${SCRIPT_DIR}/steam_shortcuts.py"
    if [[ ! -f "$SHORTCUTS_PY" ]]; then
        warn "steam_shortcuts.py not found at ${SHORTCUTS_PY} — skipping Steam auto-add."
    elif python3 "$SHORTCUTS_PY" add \
            --name "${GAME_TITLE}" \
            --exe "${LAUNCHER}" \
            --startdir "${HOME}"; then
        success "Added to Steam — restart Steam to see ${GAME_TITLE} in Gaming Mode"
    else
        warn "Could not add to Steam automatically. Use the manual steps below."
    fi
fi

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
if $INTERACTIVE; then
    echo -e "${YELLOW}${BOLD}${GAME_TITLE} — installer mode.${NC}  Follow the steps below."
else
    echo -e "${GREEN}${BOLD}${GAME_TITLE} is ready!${NC}  Enjoy your game."
fi
blank

if $INTERACTIVE; then
    echo -e "${BOLD}Installer detected — next steps:${NC}"
    blank
    echo "  1. Launch DOSBox now:   ${LAUNCHER}"
    echo "     (A DOS prompt opens at C:\\GAMES\\${GAME_UPPER})"
    blank
    echo "  2. Run the installer inside DOSBox, e.g.:"
    echo "     INSTALL.EXE   or   SETUP.EXE"
    blank
    echo "  3. When done, close DOSBox and run:"
    echo "     $0 ${GAME_LOWER} --exe <GAME.EXE>"
    echo "     This updates the launcher to start the game directly."
    blank
fi
