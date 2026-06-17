#!/usr/bin/env bash
# setup.sh — Steam Deck DOS Workstation installer
#
# Installs DOSBox Staging + RetroArch via Flatpak, creates the DOS workspace
# folder tree, deploys DOSBox configs, and installs launcher scripts.
#
# Usage:
#   bash setup.sh [--skip-flatpak] [--dry-run]
#
# Flags:
#   --skip-flatpak   Skip Flatpak installs (useful if already installed)
#   --dry-run        Print actions without executing them

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Colour helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERR ]${NC}  $*" >&2; }
header()  { echo -e "\n${BOLD}${BLUE}── $* ──${NC}"; }
step()    { echo -e "  ${CYAN}→${NC} $*"; }

DRY_RUN=false
SKIP_FLATPAK=false
for arg in "$@"; do
    case "$arg" in
        --dry-run)      DRY_RUN=true ;;
        --skip-flatpak) SKIP_FLATPAK=true ;;
        --help|-h)
            echo "Usage: $0 [--skip-flatpak] [--dry-run]"
            echo ""
            echo "  --skip-flatpak   Do not install/check Flatpak packages"
            echo "  --dry-run        Show what would be done without making changes"
            exit 0
            ;;
        *) error "Unknown argument: $arg"; exit 1 ;;
    esac
done

run() {
    if $DRY_RUN; then
        echo -e "  ${YELLOW}(dry-run)${NC} $*"
    else
        "$@"
    fi
}

# ─── Platform check ───────────────────────────────────────────────────────────
header "Steam Deck DOS Workstation Setup"
echo ""

IS_STEAMOS=false
if [[ -f /etc/os-release ]] && grep -qiE "steamos|holo" /etc/os-release 2>/dev/null; then
    IS_STEAMOS=true
    success "Running on SteamOS / Steam Deck"
else
    warn "Not running on SteamOS — some steps may not apply to your system"
fi

if ! command -v flatpak &>/dev/null; then
    error "flatpak is not available. Install it first or use --skip-flatpak."
    exit 1
fi

# ─── DOS workspace ────────────────────────────────────────────────────────────
header "Creating DOS Workspace"

DOS_ROOT="${HOME}/DOSGames"

DIRS=(
    "${DOS_ROOT}/GAMES/DOOM"
    "${DOS_ROOT}/GAMES/DUKE3D"
    "${DOS_ROOT}/GAMES/WOLF3D"
    "${DOS_ROOT}/QBASIC"
    "${DOS_ROOT}/GWBASIC"
    "${DOS_ROOT}/PROJECTS/BLACKJACK"
    "${DOS_ROOT}/PROJECTS/HANGMAN"
    "${DOS_ROOT}/PROJECTS/DEMOS"
    "${DOS_ROOT}/UTILS"
)

for d in "${DIRS[@]}"; do
    if [[ ! -d "$d" ]]; then
        step "mkdir $d"
        run mkdir -p "$d"
    fi
done
success "Workspace at ${DOS_ROOT}"

if ! $DRY_RUN; then
    cat > "${DOS_ROOT}/README.TXT" << 'EOF'
DOS WORKSTATION
===============
GAMES/          DOS games  (DOOM, DUKE3D, WOLF3D …)
  DOOM/         Place doom.wad + doom.exe here
  DUKE3D/       Place duke3d.grp + duke3d.exe here
  WOLF3D/       Place wolf3d files here
QBASIC/         QBASIC 1.1 — copy QBASIC.EXE + QBASIC.HLP here
GWBASIC/        GW-BASIC  — copy GWBASIC.EXE here
PROJECTS/       Your BASIC programs and demos
  BLACKJACK/
  HANGMAN/
  DEMOS/
UTILS/          DOS utilities (DEBUG.EXE, EDIT.COM, etc.)

Quick start in DOSBox:
  mount C ~/DOSGames
  C:
  CD QBASIC
  QBASIC.EXE
EOF
fi

# ─── Flatpak packages ─────────────────────────────────────────────────────────
DOSBOX_ID="io.github.dosbox-staging"
RETROARCH_ID="org.libretro.RetroArch"

install_flatpak() {
    local id="$1" label="$2"
    if flatpak list --user 2>/dev/null | grep -q "$id" || \
       flatpak list        2>/dev/null | grep -q "$id"; then
        success "$label already installed"
        return 0
    fi
    info "Installing $label …"
    if run flatpak install --user --assumeyes flathub "$id"; then
        success "$label installed"
    else
        error "Failed to install $label"
        echo "  Manual install:  flatpak install --user flathub $id"
        return 1
    fi
}

if ! $SKIP_FLATPAK; then
    header "Installing Flatpak Packages"

    # Ensure flathub remote exists
    if ! flatpak remotes --user 2>/dev/null | grep -q flathub && \
       ! flatpak remotes        2>/dev/null | grep -q flathub; then
        info "Adding Flathub remote …"
        run flatpak remote-add --user --if-not-exists flathub \
            https://dl.flathub.org/repo/flathub.flatpakrepo
    fi

    install_flatpak "$DOSBOX_ID"   "DOSBox Staging" || true
    install_flatpak "$RETROARCH_ID" "RetroArch"      || true
fi

# ─── DOSBox Staging configuration ────────────────────────────────────────────
header "Deploying DOSBox Staging Config"

DOSBOX_CFG_DIR="${HOME}/.var/app/${DOSBOX_ID}/config/dosbox"

if ! $DRY_RUN; then
    mkdir -p "$DOSBOX_CFG_DIR"
fi

deploy_config() {
    local src="$1" dst="$2"
    # Expand __HOME__ placeholder to actual home directory
    if [[ -f "$src" ]]; then
        if $DRY_RUN; then
            step "deploy $src → $dst  (HOME=${HOME})"
        else
            if [[ -f "$dst" ]]; then
                local bak="${dst}.bak.$(date +%Y%m%d%H%M%S)"
                cp "$dst" "$bak"
                warn "Backed up existing config → $bak"
            fi
            sed "s|__HOME__|${HOME}|g" "$src" > "$dst"
            success "Deployed: $dst"
        fi
    else
        warn "Source config not found: $src"
    fi
}

deploy_config \
    "${SCRIPT_DIR}/configs/dosbox-staging.conf" \
    "${DOSBOX_CFG_DIR}/dosbox-staging.conf"

deploy_config \
    "${SCRIPT_DIR}/configs/dosbox-qbasic.conf" \
    "${DOSBOX_CFG_DIR}/dosbox-qbasic.conf"

# ─── Launcher scripts ─────────────────────────────────────────────────────────
header "Installing Launcher Scripts"

BIN_DIR="${HOME}/.local/bin"
if ! $DRY_RUN; then mkdir -p "$BIN_DIR"; fi

for launcher in launch_dos.sh launch_qbasic.sh; do
    src="${SCRIPT_DIR}/launchers/${launcher}"
    dst="${BIN_DIR}/${launcher}"
    if [[ -f "$src" ]]; then
        step "install $dst"
        if ! $DRY_RUN; then
            cp "$src" "$dst"
            chmod +x "$dst"
        fi
        success "Installed: $dst"
    else
        warn "Launcher not found: $src"
    fi
done

# ─── Desktop shortcuts ────────────────────────────────────────────────────────
header "Creating Desktop Shortcuts"

DESKTOP_DIR="${HOME}/.local/share/applications"
if ! $DRY_RUN; then mkdir -p "$DESKTOP_DIR"; fi

write_desktop() {
    local file="$1"; shift
    step "write $file"
    if ! $DRY_RUN; then
        cat > "$file"
        success "Created: $file"
    fi
}

write_desktop "${DESKTOP_DIR}/dos-workspace.desktop" << EOF
[Desktop Entry]
Name=DOS Workspace
Comment=Launch DOSBox Staging with the DOS workspace
Exec=${BIN_DIR}/launch_dos.sh
Icon=io.github.dosbox-staging
Terminal=false
Type=Application
Categories=Game;Emulator;
StartupNotify=false
EOF

write_desktop "${DESKTOP_DIR}/dos-qbasic.desktop" << EOF
[Desktop Entry]
Name=QBASIC Dev
Comment=QBASIC 1.1 development environment
Exec=${BIN_DIR}/launch_qbasic.sh
Icon=io.github.dosbox-staging
Terminal=false
Type=Application
Categories=Development;Emulator;
StartupNotify=false
EOF

# ─── Summary ──────────────────────────────────────────────────────────────────
header "Setup Complete"
echo ""
echo -e "${BOLD}Required files (not included — obtain legally):${NC}"
echo ""
echo "  QBASIC 1.1 → ${DOS_ROOT}/QBASIC/"
echo "    QBASIC.EXE  (from MS-DOS 5/6 or FreeDOS)"
echo "    QBASIC.HLP  (optional; enables inline help)"
echo ""
echo "  GW-BASIC   → ${DOS_ROOT}/GWBASIC/"
echo "    GWBASIC.EXE"
echo ""
echo -e "${BOLD}Add to Steam (Desktop Mode):${NC}"
echo "  1. Open Steam → Games → Add a Non-Steam Game"
echo "  2. Browse → ${BIN_DIR}/launch_dos.sh    (DOS Workspace)"
echo "  3. Browse → ${BIN_DIR}/launch_qbasic.sh  (QBASIC Dev)"
echo ""
echo -e "${BOLD}Recommended Steam Input layout (for each shortcut):${NC}"
echo "  Left Trackpad    → Mouse"
echo "  Right Stick      → Mouse"
echo "  Left  Trigger    → Left Mouse Click"
echo "  Right Trigger    → Right Mouse Click"
echo "  A                → Enter"
echo "  B                → Escape"
echo "  Steam + X        → On-screen keyboard"
echo ""
echo -e "${GREEN}Done!${NC}  Launch 'DOS Workspace' from Desktop or Gaming Mode."
echo ""
