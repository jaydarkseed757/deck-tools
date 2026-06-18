#!/usr/bin/env bash
# dos-game-list.sh — Show all deployed DOS games and their status

set -euo pipefail

DOSBOX_ID="io.github.dosbox-staging"
GAMES_DIR="${HOME}/DOSGames/GAMES"
CFG_DIR="${HOME}/.var/app/${DOSBOX_ID}/config/dosbox"
BIN_DIR="${HOME}/.local/bin"
APP_DIR="${HOME}/.local/share/applications"

CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

if [[ ! -d "$GAMES_DIR" ]]; then
    echo "No DOS games directory found at ${GAMES_DIR}"
    echo "Run setup.sh to create the workspace."
    exit 1
fi

shopt -s nullglob
game_dirs=("${GAMES_DIR}"/*/); shopt -u nullglob

if [[ ${#game_dirs[@]} -eq 0 ]]; then
    echo "No games deployed yet."
    echo "Use dos-game-deploy.sh to add a game."
    exit 0
fi

printf "\n${BOLD}${CYAN}%-12s %-16s %-7s %-9s %-9s${NC}\n" \
    "GAME" "EXE" "CONFIG" "LAUNCHER" "SHORTCUT"
printf '─%.0s' {1..55}; echo

for game_dir in "${game_dirs[@]}"; do
    [[ -d "$game_dir" ]] || continue
    raw="${game_dir%/}"; raw="${raw##*/}"
    lower="${raw,,}"

    exe="$(find "$game_dir" -maxdepth 1 -iname "*.exe" -printf "%f\n" 2>/dev/null | sort | head -1)"
    [[ -z "$exe" ]] && exe="-"

    cfg="${CFG_DIR}/dosbox-${lower}.conf"
    launcher="${BIN_DIR}/launch_${lower}.sh"
    desktop="${APP_DIR}/dos-${lower}.desktop"

    [[ -f "$cfg"      ]] && cfg_s="OK" || cfg_s="--"
    [[ -f "$launcher" ]] && run_s="OK" || run_s="--"
    [[ -f "$desktop"  ]] && dsk_s="OK" || dsk_s="--"

    printf "%-12s %-16s %-7s %-9s %-9s\n" \
        "${lower}" "${exe^^}" "${cfg_s}" "${run_s}" "${dsk_s}"
done
echo
