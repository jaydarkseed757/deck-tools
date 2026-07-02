#!/usr/bin/env bash
# install.sh — One-command installer for deck-tools DOS Workstation
#
# Run from a Steam Deck terminal (Desktop Mode → Konsole):
#   bash <(curl -sSL https://raw.githubusercontent.com/jaydarkseed757/deck-tools/main/install.sh)
#
# Or install remotely over SSH from your laptop/desktop:
#   ssh deck@<DECK-IP> 'bash <(curl -sSL https://raw.githubusercontent.com/jaydarkseed757/deck-tools/main/install.sh)'
#
# All arguments are forwarded to setup.sh, e.g.:
#   ... | bash -s -- --dry-run
#   ... | bash -s -- --skip-flatpak

set -euo pipefail

REPO="jaydarkseed757/deck-tools"
BRANCH="main"
ARCHIVE="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"
DEST="${HOME}/.local/share/deck-tools"

# ─── Colour helpers ───────────────────────────────────────────────────────────
CYAN='\033[0;36m'; GREEN='\033[0;32m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[ OK ]${NC}  $*"; }

# ─── Help passthrough ─────────────────────────────────────────────────────────
for arg in "$@"; do
    if [[ "$arg" == "--help" || "$arg" == "-h" ]]; then
        echo "install.sh — fetch and run the deck-tools DOS Workstation setup"
        echo ""
        echo "Usage:"
        echo "  bash <(curl -sSL https://raw.githubusercontent.com/${REPO}/main/install.sh) [OPTIONS]"
        echo ""
        echo "Options are forwarded to setup.sh:"
        echo "  --dry-run        Print actions without making changes"
        echo "  --skip-flatpak   Skip DOSBox Staging / RetroArch installation"
        echo "  --help           Show this message"
        echo ""
        echo "SSH remote install:"
        echo "  ssh deck@<IP> 'bash <(curl -sSL https://raw.githubusercontent.com/${REPO}/main/install.sh)'"
        exit 0
    fi
done

# ─── Dependency check ─────────────────────────────────────────────────────────
if ! command -v curl &>/dev/null; then
    echo "Error: curl is required but not found." >&2
    exit 1
fi
if ! command -v tar &>/dev/null; then
    echo "Error: tar is required but not found." >&2
    exit 1
fi

# ─── Download repo ────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}deck-tools DOS Workstation Installer${NC}"
echo ""
info "Downloading deck-tools from GitHub …"

# Start from a clean slate — extracting over an old tree would leave files
# deleted upstream lingering (and runnable). $DEST is dedicated to this tool.
rm -rf "$DEST"
mkdir -p "$DEST"
# -f: fail on HTTP errors instead of piping an HTML error page into tar
curl -sSfL "$ARCHIVE" | tar -xz --strip-components=1 -C "$DEST"

success "Saved to ${DEST}"
echo ""

# ─── Run setup ────────────────────────────────────────────────────────────────
exec bash "${DEST}/dos-workstation/setup.sh" "$@"
