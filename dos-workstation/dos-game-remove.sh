#!/usr/bin/env bash
# dos-game-remove.sh — Remove a deployed DOS game and all its artifacts
#
# Usage:
#   dos-game-remove.sh <game-name> [--keep-files]
#
# Removes:
#   ~/DOSGames/GAMES/<GAME>/              (skipped with --keep-files)
#   ~/.var/app/.../dosbox-<game>.conf
#   ~/.local/bin/launch_<game>.sh
#   ~/.local/share/applications/dos-<game>.desktop
#   Steam shortcut entry (if steam_shortcuts.py is available)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERR ]${NC}  $*" >&2; }

usage() {
    echo "Usage: $0 <game-name> [--keep-files]"
    echo ""
    echo "  game-name      Name of the deployed game (e.g. quake, doom)"
    echo "  --keep-files   Remove config/launcher/shortcut but keep game files"
    echo ""
    echo "Examples:"
    echo "  $0 quake"
    echo "  $0 doom --keep-files"
}

KEEP_FILES=false
GAME_RAW=""

for arg in "$@"; do
    case "$arg" in
        --keep-files) KEEP_FILES=true ;;
        --help|-h)    usage; exit 0 ;;
        -*)           error "Unknown flag: $arg"; usage; exit 1 ;;
        *)            GAME_RAW="$arg" ;;
    esac
done

if [[ -z "$GAME_RAW" ]]; then
    error "A game name is required."
    echo ""
    usage
    exit 1
fi

# The name becomes the path component that gets rm -rf'd — a '/' or '..'
# would escape ~/DOSGames/GAMES (e.g. '../GAMES' resolves to the GAMES dir
# itself and would delete every game).
if [[ "$GAME_RAW" == */* || "$GAME_RAW" == *..* ]]; then
    error "Invalid game name '${GAME_RAW}' — must not contain '/' or '..'"
    exit 1
fi

GAME_LOWER="${GAME_RAW,,}"
GAME_UPPER="${GAME_RAW^^}"
# Derive the title the same way dos-game-deploy.sh does — from the raw argument,
# preserving the case of everything after the first character. Deriving from
# GAME_LOWER instead would force the tail lowercase and fail to match a Steam
# shortcut that was deployed with a mixed/upper-case name (e.g. WOLF3D).
GAME_TITLE="$(tr '[:lower:]' '[:upper:]' <<< "${GAME_RAW:0:1}")${GAME_RAW:1}"

DOSBOX_ID="io.github.dosbox-staging"
GAME_DIR="${HOME}/DOSGames/GAMES/${GAME_UPPER}"
GAME_CFG="${HOME}/.var/app/${DOSBOX_ID}/config/dosbox/dosbox-${GAME_LOWER}.conf"
LAUNCHER="${HOME}/.local/bin/launch_${GAME_LOWER}.sh"
DESKTOP="${HOME}/.local/share/applications/dos-${GAME_LOWER}.desktop"
SHORTCUTS_PY="${SCRIPT_DIR}/steam_shortcuts.py"

echo ""
echo -e "${BOLD}Removing: ${GAME_TITLE}${NC}"
echo ""

# Inventory what exists
TO_REMOVE=()
if ! $KEEP_FILES && [[ -d "$GAME_DIR" ]]; then
    TO_REMOVE+=("$GAME_DIR")
fi
[[ -f "$GAME_CFG"   ]] && TO_REMOVE+=("$GAME_CFG")
[[ -f "$LAUNCHER"   ]] && TO_REMOVE+=("$LAUNCHER")
[[ -f "$DESKTOP"    ]] && TO_REMOVE+=("$DESKTOP")

# Detect the Steam shortcut BEFORE deciding there's nothing to do — a
# shortcut can outlive the local artifacts (orphan) and must still be
# removable on its own.
HAS_STEAM_ENTRY=false
if [[ -f "$SHORTCUTS_PY" ]]; then
    # Match the AppName field (tab-delimited, first column) exactly.
    # -F (fixed string) avoids treating names with regex metacharacters
    # (. + ( ) etc.) as patterns; -x anchors to the whole field.
    if python3 "$SHORTCUTS_PY" list 2>/dev/null | cut -f1 | grep -Fxqi -- "${GAME_TITLE}"; then
        HAS_STEAM_ENTRY=true
    fi
fi

if [[ ${#TO_REMOVE[@]} -eq 0 ]] && ! $HAS_STEAM_ENTRY; then
    warn "Nothing found to remove for '${GAME_LOWER}'."
    exit 0
fi

echo "Will remove:"
for item in "${TO_REMOVE[@]+"${TO_REMOVE[@]}"}"; do
    echo "  $item"
done
if $HAS_STEAM_ENTRY; then
    echo "  Steam shortcut: ${GAME_TITLE}"
fi

echo ""
# `|| REPLY=""` keeps set -e from aborting on EOF when stdin is not a TTY;
# an empty reply falls through to the default-deny branch below.
read -rp "Confirm removal? [y/N] " REPLY || REPLY=""
if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    info "Cancelled."
    exit 0
fi

echo ""

for item in "${TO_REMOVE[@]+"${TO_REMOVE[@]}"}"; do
    if [[ -d "$item" ]]; then
        rm -rf "$item"
        success "Removed: $item"
    elif [[ -f "$item" ]]; then
        rm -f "$item"
        success "Removed: $item"
    fi
done

if $HAS_STEAM_ENTRY && [[ -f "$SHORTCUTS_PY" ]]; then
    if python3 "$SHORTCUTS_PY" remove --name "${GAME_TITLE}" 2>/dev/null; then
        success "Removed Steam shortcut: ${GAME_TITLE}"
        warn "Restart Steam for the change to take effect."
    else
        warn "Could not remove Steam shortcut automatically — remove it manually in Steam."
    fi
fi

echo ""
echo -e "${GREEN}${BOLD}${GAME_TITLE} removed.${NC}"
echo ""
