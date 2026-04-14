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
SKIP_SD=0
CLEAN_MODE=0
GAME_FILTER=""
CSV_MODE=0
JSON_MODE=0
WARN_AT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            echo "Usage: $(basename "$0") [OPTIONS]"
            echo ""
            echo "Shows shader cache and compatdata usage on Steam Deck."
            echo ""
            echo "Options:"
            echo "  --clean          Scan for orphaned cache entries and offer to delete them"
            echo "  --csv            Export report as CSV (type,location,appid,name,size_bytes)"
            echo "  --game <name>    Show cache usage for a specific game (partial name match)"
            echo "  --json           Export report as JSON"
            echo "  --nosd           Skip SD card storage scan"
            echo "  --top <N>        Show top N entries per section (default: 10)"
            echo "  --warn-at <size> Warn if total cache usage exceeds size (e.g. 20G, 500M)"
            echo "  --help           Show this help message"
            echo ""
            echo "Source: https://github.com/jaydarkseed757/deck-tools"
            exit 0
            ;;
        --nosd)
            SKIP_SD=1
            ;;
        --clean)
            CLEAN_MODE=1
            ;;
        --csv)
            CSV_MODE=1
            ;;
        --json)
            JSON_MODE=1
            ;;
        --warn-at)
            if [[ -z "$2" || ! "${2^^}" =~ ^[0-9]+(\.[0-9]+)?(T|G|M|K)(I?B)?$ ]]; then
                echo "Error: --warn-at requires a size argument (e.g. 20G, 500M, 1.5T)" >&2
                echo "Run '$(basename "$0") --help' for usage." >&2
                exit 1
            fi
            WARN_AT="$2"
            shift
            ;;
        --game)
            if [[ -z "$2" || "$2" == --* ]]; then
                echo "Error: --game requires a name argument" >&2
                echo "Run '$(basename "$0") --help' for usage." >&2
                exit 1
            fi
            GAME_FILTER="$2"
            shift
            ;;
        --top)
            if [[ -z "$2" || ! "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: --top requires a positive integer argument" >&2
                echo "Run '$(basename "$0") --help' for usage." >&2
                exit 1
            fi
            TOP_N="$2"
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Run '$(basename "$0") --help' for usage." >&2
            exit 1
            ;;
    esac
    shift
done

parse_size() {
    local input="${1^^}"
    if [[ "$input" =~ ^([0-9]+(\.[0-9]+)?)(T|G|M|K) ]]; then
        local num="${BASH_REMATCH[1]}"
        local unit="${BASH_REMATCH[3]}"
        case "$unit" in
            T) awk "BEGIN {printf \"%d\", $num * 1099511627776}" ;;
            G) awk "BEGIN {printf \"%d\", $num * 1073741824}" ;;
            M) awk "BEGIN {printf \"%d\", $num * 1048576}" ;;
            K) awk "BEGIN {printf \"%d\", $num * 1024}" ;;
        esac
    else
        echo ""
    fi
}

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

clean_mode() {
    section "ORPHAN SCAN"
    echo ""

    # Collect installed appids from all manifest files
    declare -A installed
    for manifest in "$HOME/.local/share/Steam/steamapps"/appmanifest_*.acf; do
        [[ -f "$manifest" ]] || continue
        appid=$(basename "$manifest" .acf)
        installed["${appid#appmanifest_}"]=1
    done
    if [[ $SKIP_SD -eq 0 ]]; then
        for manifest in "$SD_BASE"/*/steamapps/appmanifest_*.acf; do
            [[ -f "$manifest" ]] || continue
            appid=$(basename "$manifest" .acf)
            installed["${appid#appmanifest_}"]=1
        done
    fi

    # Build list of dirs to scan
    scan_dirs=("$INTERNAL_SHADER" "$INTERNAL_COMPAT")
    if [[ $SKIP_SD -eq 0 ]]; then
        for d in "$SD_BASE"/*/steamapps/shadercache "$SD_BASE"/*/steamapps/compatdata; do
            [[ -d "$d" ]] && scan_dirs+=("$d")
        done
    fi

    # Find orphaned entries (cache dirs with no matching appmanifest)
    orphans=()
    for dir in "${scan_dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        for entry in "$dir"/*/; do
            [[ -d "$entry" ]] || continue
            appid=$(basename "$entry")
            if [[ -z "${installed[$appid]+x}" ]]; then
                orphans+=("$entry")
            fi
        done
    done

    if [[ ${#orphans[@]} -eq 0 ]]; then
        echo -e "  ${GREEN}No orphaned entries found.${RESET}"
        echo ""
        separator
        echo ""
        return
    fi

    echo -e "  ${BOLD}Found ${#orphans[@]} orphaned entries:${RESET}"
    echo ""

    total_bytes=0
    declare -a orphan_sizes
    for i in "${!orphans[@]}"; do
        entry="${orphans[$i]}"
        appid=$(basename "$entry")
        name=$(get_app_name "$appid")
        size_bytes=$(du -sb "$entry" 2>/dev/null | cut -f1)
        size_hr=$(du -sh "$entry" 2>/dev/null | cut -f1)
        orphan_sizes[$i]="$size_hr"
        total_bytes=$((total_bytes + size_bytes))
        printf "  ${YELLOW}[%d]${RESET} ${YELLOW}%-8s${RESET}  %s\n" "$((i+1))" "$size_hr" "$name"
        echo -e "       ${CYAN}$entry${RESET}"
        echo ""
    done

    total_hr=$(numfmt --to=iec-i --suffix=B "$total_bytes" 2>/dev/null || echo "N/A")
    echo -e "  ${GREEN}Total recoverable: ${BOLD}$total_hr${RESET}"
    echo ""
    separator
    echo ""

    echo -e "  ${BOLD}What would you like to do?${RESET}"
    echo -e "  ${YELLOW}[a]${RESET} Delete all"
    echo -e "  ${YELLOW}[p]${RESET} Pick one by one"
    echo -e "  ${YELLOW}[q]${RESET} Quit without deleting"
    echo ""
    read -rp "  Choice: " choice

    case "$choice" in
        a|A)
            echo ""
            for entry in "${orphans[@]}"; do
                rm -rf "$entry"
                echo -e "  ${RED}Deleted:${RESET} $entry"
            done
            echo -e "\n  ${GREEN}Done.${RESET}"
            ;;
        p|P)
            echo ""
            for i in "${!orphans[@]}"; do
                entry="${orphans[$i]}"
                appid=$(basename "$entry")
                name=$(get_app_name "$appid")
                printf "  Delete ${YELLOW}%s${RESET} (%s)? [y/N/q] " "$name" "${orphan_sizes[$i]}"
                read -rp "" resp
                case "$resp" in
                    y|Y) rm -rf "$entry"; echo -e "  ${RED}Deleted.${RESET}" ;;
                    q|Q) echo -e "  ${YELLOW}Stopped.${RESET}"; break ;;
                    *)   echo -e "  Skipped." ;;
                esac
            done
            echo -e "\n  ${GREEN}Done.${RESET}"
            ;;
        *)
            echo -e "\n  ${YELLOW}No changes made.${RESET}"
            ;;
    esac

    echo ""
    separator
    echo ""
}

csv_mode() {
    echo "type,location,appid,name,size_bytes"

    csv_scan_dir() {
        local type="$1"   # shadercache or compatdata
        local location="$2"  # internal or sd_card
        local base_dir="$3"

        [[ -d "$base_dir" ]] || return

        for entry in "$base_dir"/*/; do
            [[ -d "$entry" ]] || continue
            local appid
            appid=$(basename "$entry")
            local name
            name=$(get_app_name "$appid")
            local size_bytes
            size_bytes=$(du -sb "$entry" 2>/dev/null | cut -f1)
            # Escape any commas or quotes in name
            name="${name//\"/\"\"}"
            echo "\"$type\",\"$location\",\"$appid\",\"$name\",\"$size_bytes\""
        done
    }

    csv_scan_dir "shadercache" "internal" "$INTERNAL_SHADER"
    csv_scan_dir "compatdata"  "internal" "$INTERNAL_COMPAT"

    if [[ $SKIP_SD -eq 0 ]]; then
        for sd_path in "$SD_BASE"/*/steamapps; do
            [[ -d "$sd_path" ]] || continue
            csv_scan_dir "shadercache" "sd_card" "$sd_path/shadercache"
            csv_scan_dir "compatdata"  "sd_card" "$sd_path/compatdata"
        done
    fi
}

json_mode() {
    local first=1
    echo '{"entries": ['

    json_scan_dir() {
        local type="$1"
        local location="$2"
        local base_dir="$3"

        [[ -d "$base_dir" ]] || return

        for entry in "$base_dir"/*/; do
            [[ -d "$entry" ]] || continue
            local appid
            appid=$(basename "$entry")
            local name
            name=$(get_app_name "$appid")
            local size_bytes
            size_bytes=$(du -sb "$entry" 2>/dev/null | cut -f1)
            # Escape backslashes then quotes in name
            name="${name//\\/\\\\}"
            name="${name//\"/\\\"}"
            if [[ $first -eq 0 ]]; then echo ","; fi
            printf '  {"type": "%s", "location": "%s", "appid": "%s", "name": "%s", "size_bytes": %s}' \
                "$type" "$location" "$appid" "$name" "$size_bytes"
            first=0
        done
    }

    json_scan_dir "shadercache" "internal" "$INTERNAL_SHADER"
    json_scan_dir "compatdata"  "internal" "$INTERNAL_COMPAT"

    if [[ $SKIP_SD -eq 0 ]]; then
        for sd_path in "$SD_BASE"/*/steamapps; do
            [[ -d "$sd_path" ]] || continue
            json_scan_dir "shadercache" "sd_card" "$sd_path/shadercache"
            json_scan_dir "compatdata"  "sd_card" "$sd_path/compatdata"
        done
    fi

    echo ""
    echo "]}"
}

game_mode() {
    section "GAME LOOKUP: $GAME_FILTER"
    echo ""

    # Search a steamapps dir for manifests matching the game name
    declare -A matches  # appid -> name
    search_dir() {
        local dir="$1"
        for manifest in "$dir"/appmanifest_*.acf; do
            [[ -f "$manifest" ]] || continue
            name=$(grep -i '"name"' "$manifest" | head -1 | awk -F'"' '{print $4}')
            if echo "$name" | grep -qi "$GAME_FILTER"; then
                local appid
                appid=$(basename "$manifest" .acf)
                matches["${appid#appmanifest_}"]="$name"
            fi
        done
    }

    search_dir "$HOME/.local/share/Steam/steamapps"
    if [[ $SKIP_SD -eq 0 ]]; then
        for sd in "$SD_BASE"/*/steamapps; do
            [[ -d "$sd" ]] && search_dir "$sd"
        done
    fi

    if [[ ${#matches[@]} -eq 0 ]]; then
        echo -e "  ${RED}No installed games found matching: $GAME_FILTER${RESET}"
        echo ""
        separator
        echo ""
        return
    fi

    for appid in "${!matches[@]}"; do
        name="${matches[$appid]}"
        echo -e "  ${BOLD}$name${RESET}  ${CYAN}(App ID: $appid)${RESET}"
        echo ""

        found_any=0
        for dir in \
            "$INTERNAL_SHADER/$appid" \
            "$INTERNAL_COMPAT/$appid" \
            "$SD_BASE"/*/steamapps/shadercache/"$appid" \
            "$SD_BASE"/*/steamapps/compatdata/"$appid"; do
            [[ -d "$dir" ]] || continue
            found_any=1
            size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            printf "  ${YELLOW}%-8s${RESET}  %s\n" "$size" "$dir"
        done

        if [[ $found_any -eq 0 ]]; then
            echo -e "  ${YELLOW}No cache entries found for this game.${RESET}"
        fi
        echo ""
    done

    separator
    echo ""
}

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║       Steam Deck Shader Cache Report         ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════╝${RESET}"

if [[ $CSV_MODE -eq 1 ]]; then
    csv_mode
    exit 0
fi

if [[ $JSON_MODE -eq 1 ]]; then
    json_mode
    exit 0
fi

if [[ $CLEAN_MODE -eq 1 ]]; then
    clean_mode
    exit 0
fi

if [[ -n "$GAME_FILTER" ]]; then
    game_mode
    exit 0
fi

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
if [[ $SKIP_SD -eq 0 ]]; then
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
fi  # end SKIP_SD check

# ── Summary ───────────────────────────────────────────────
section "SUMMARY"

echo ""
summary_dirs=("$INTERNAL_SHADER" "$INTERNAL_COMPAT")
if [[ $SKIP_SD -eq 0 ]]; then
    for d in "$SD_BASE"/*/steamapps/shadercache "$SD_BASE"/*/steamapps/compatdata; do
        summary_dirs+=("$d")
    done
fi
for dir in "${summary_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    size=$(du -sh "$dir" 2>/dev/null | cut -f1)
    printf "  ${YELLOW}%-8s${RESET}  %s\n" "$size" "$dir"
done

if [[ -n "$WARN_AT" ]]; then
    warn_bytes=$(parse_size "$WARN_AT")
    all_dirs=("$INTERNAL_SHADER" "$INTERNAL_COMPAT")
    if [[ $SKIP_SD -eq 0 ]]; then
        for d in "$SD_BASE"/*/steamapps/shadercache "$SD_BASE"/*/steamapps/compatdata; do
            [[ -d "$d" ]] && all_dirs+=("$d")
        done
    fi
    total_bytes=$(du -sbc "${all_dirs[@]}" 2>/dev/null | tail -1 | awk '{print $1}')
    if [[ -n "$total_bytes" && -n "$warn_bytes" && "$total_bytes" -gt "$warn_bytes" ]]; then
        total_hr=$(numfmt --to=iec-i --suffix=B "$total_bytes" 2>/dev/null || echo "N/A")
        echo ""
        echo -e "  ${RED}${BOLD}WARNING:${RESET}${RED} Total cache usage ($total_hr) exceeds --warn-at threshold ($WARN_AT)${RESET}"
    fi
fi

echo ""
separator
echo ""
