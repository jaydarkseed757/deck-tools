#!/bin/bash
# shader_cache_report.sh
# Shows shader cache and compatdata usage on Steam Deck (internal + SD card)

BOLD='\033[1m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
RESET='\033[0m'

INTERNAL_SHADER="$HOME/.local/share/Steam/steamapps/shadercache"
INTERNAL_COMPAT="$HOME/.local/share/Steam/steamapps/compatdata"
SD_BASE="/run/media"

TOP_N=10  # How many top entries to show per section

separator() {
    echo -e "${CYAN}────────────────────────────────────────────────────────${RESET}"
}

section() {
    echo ""
    separator
    echo -e "${BOLD}${CYAN}$1${RESET}"
    separator
}

# Lookup app name from Steam appinfo if available
get_app_name() {
    local appid="$1"
    local name=""

    # Try to find the name from installed apps via Steam's config
    if command -v python3 &>/dev/null; then
        name=$(python3 -c "
import os, glob
appid = '$appid'
# Search for appmanifest files
patterns = [
    os.path.expanduser('~/.local/share/Steam/steamapps/appmanifest_{}.acf'.format(appid)),
]
# Also check SD card locations
for d in glob.glob('/run/media/*/steamapps/appmanifest_{}.acf'.format(appid)):
    patterns.append(d)
for path in patterns:
    if os.path.exists(path):
        with open(path) as f:
            for line in f:
                if '\"name\"' in line.lower():
                    parts = line.strip().split('\t')
                    parts = [p.strip('\"') for p in parts if p.strip('\"')]
                    if len(parts) >= 2:
                        print(parts[-1])
                        exit()
" 2>/dev/null)
    fi

    if [[ -n "$name" ]]; then
        echo "$name"
    else
        echo "App ID: $appid"
    fi
}

print_dir_breakdown() {
    local base_dir="$1"
    local label="$2"

    if [[ ! -d "$base_dir" ]]; then
        echo -e "  ${RED}Directory not found: $base_dir${RESET}"
        return
    fi

    local total
    total=$(du -sh "$base_dir" 2>/dev/null | cut -f1)
    echo -e "  ${GREEN}Total:${RESET} ${BOLD}$total${RESET}  ${YELLOW}($label)${RESET}"
    echo ""

    echo -e "  ${BOLD}Top $TOP_N entries by size:${RESET}"
    echo ""

    local count=0
    while IFS=$'\t' read -r size path; do
        local appid
        appid=$(basename "$path")
        local name
        name=$(get_app_name "$appid")
        printf "  ${YELLOW}%-8s${RESET}  %s\n" "$size" "$name"
        ((count++))
        [[ $count -ge $TOP_N ]] && break
    done < <(du -sh "$base_dir"/* 2>/dev/null | sort -rh)
}

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║       Steam Deck Shader Cache Report         ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════╝${RESET}"

# ── Internal Storage ──────────────────────────────────────
section "INTERNAL STORAGE"

echo -e "\n  ${BOLD}Shader Cache${RESET}"
print_dir_breakdown "$INTERNAL_SHADER" "shadercache"

echo -e "\n  ${BOLD}Proton Compatibility Data${RESET}"
print_dir_breakdown "$INTERNAL_COMPAT" "compatdata"

# Combined internal total
if [[ -d "$INTERNAL_SHADER" || -d "$INTERNAL_COMPAT" ]]; then
    combined=$(du -sbc "$INTERNAL_SHADER" "$INTERNAL_COMPAT" 2>/dev/null | tail -1 | awk '{print $1}')
    combined_hr=$(numfmt --to=iec-i --suffix=B "$combined" 2>/dev/null || echo "N/A")
    echo ""
    echo -e "  ${GREEN}Combined internal total:${RESET} ${BOLD}$combined_hr${RESET}"
fi

# ── SD Card Storage ───────────────────────────────────────
section "SD CARD STORAGE"

sd_found=0
for sd_path in "$SD_BASE"/*/steamapps; do
    [[ -d "$sd_path" ]] || continue
    sd_found=1
    sd_label=$(echo "$sd_path" | awk -F'/' '{print $4}')

    echo -e "\n  ${BOLD}SD Card: ${YELLOW}$sd_label${RESET}"

    sd_shader="$sd_path/shadercache"
    sd_compat="$sd_path/compatdata"

    echo -e "\n  ${BOLD}Shader Cache${RESET}"
    print_dir_breakdown "$sd_shader" "shadercache"

    echo -e "\n  ${BOLD}Proton Compatibility Data${RESET}"
    print_dir_breakdown "$sd_compat" "compatdata"
done

if [[ $sd_found -eq 0 ]]; then
    echo -e "  ${YELLOW}No SD card detected at $SD_BASE${RESET}"
fi

# ── Summary ───────────────────────────────────────────────
section "SUMMARY"

echo ""
for dir in "$INTERNAL_SHADER" "$INTERNAL_COMPAT" "$SD_BASE"/*/steamapps/shadercache "$SD_BASE"/*/steamapps/compatdata; do
    [[ -d "$dir" ]] || continue
    size=$(du -sh "$dir" 2>/dev/null | cut -f1)
    printf "  ${YELLOW}%-8s${RESET}  %s\n" "$size" "$dir"
done

echo ""
separator
echo ""
