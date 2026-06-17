#!/usr/bin/env bash
# launch_qbasic.sh — Launch QBASIC 1.1 development environment
#
# Boots straight into the QBASIC IDE.  If QBASIC.EXE is missing the
# DOSBox autoexec will print a helpful error instead of hanging.
#
# Add this script as a non-Steam game for one-tap QBASIC from Gaming Mode.
#
# Optional: pass a .BAS filename to open it directly, e.g.
#   launch_qbasic.sh PROJECTS/BLACKJACK/BLACKJACK.BAS

DOSBOX_ID="io.github.dosbox-staging"
QBASIC_CFG="${HOME}/.var/app/${DOSBOX_ID}/config/dosbox/dosbox-qbasic.conf"
DOS_ROOT="${HOME}/DOSGames"
BAS_FILE="${1:-}"

if ! flatpak list --user 2>/dev/null | grep -q "$DOSBOX_ID" && \
   ! flatpak list        2>/dev/null | grep -q "$DOSBOX_ID"; then
    echo "DOSBox Staging is not installed."
    echo "Run setup.sh first, or install manually:"
    echo "  flatpak install --user flathub ${DOSBOX_ID}"
    exit 1
fi

if [[ ! -f "$QBASIC_CFG" ]]; then
    echo "Config not found: $QBASIC_CFG"
    echo "Run setup.sh to deploy the configuration."
    exit 1
fi

# If a .BAS file was passed, open it directly in QBASIC
if [[ -n "$BAS_FILE" ]]; then
    # Resolve to a DOS path relative to the C: mount
    DOS_PATH="${BAS_FILE#"${DOS_ROOT}/"}"   # strip leading DOS_ROOT if present
    DOS_PATH="${DOS_PATH^^}"                # uppercase (DOS convention)
    DOS_PATH="${DOS_PATH//\//\\}"           # forward → back slashes

    exec flatpak run "$DOSBOX_ID" \
        --conf "$QBASIC_CFG" \
        -c "CD QBASIC" \
        -c "QBASIC.EXE /RUN C:\\${DOS_PATH}"
fi

exec flatpak run "$DOSBOX_ID" --conf "$QBASIC_CFG"
