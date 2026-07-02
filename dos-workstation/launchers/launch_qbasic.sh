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
CFG_DIR="${HOME}/.var/app/${DOSBOX_ID}/config/dosbox"
QBASIC_CFG="${CFG_DIR}/dosbox-qbasic.conf"
STAGING_CFG="${CFG_DIR}/dosbox-staging.conf"
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

# If a .BAS file was passed, open it directly in QBASIC.
# Use the general staging config (not dosbox-qbasic.conf): its autoexec only
# mounts C: and returns to the prompt, so DOSBox then runs the -c commands.
# dosbox-qbasic.conf would auto-launch the QBASIC IDE first and block, and the
# -c commands would not run until that interactive session was quit.
if [[ -n "$BAS_FILE" ]]; then
    if [[ ! -f "$STAGING_CFG" ]]; then
        echo "Config not found: $STAGING_CFG"
        echo "Run setup.sh to deploy the configuration."
        exit 1
    fi

    # The qbasic config's missing-EXE guard doesn't apply on this path (we use
    # the staging config), so check here — otherwise the user just gets DOS's
    # "Bad command or file name" with no explanation.
    if [[ ! -f "${DOS_ROOT}/QBASIC/QBASIC.EXE" ]]; then
        echo "QBASIC.EXE not found in ${DOS_ROOT}/QBASIC/"
        echo "Copy QBASIC.EXE (and QBASIC.HLP) from MS-DOS 5/6 or FreeDOS there first."
        exit 1
    fi

    # Resolve to a DOS path relative to the C: mount
    DOS_PATH="${BAS_FILE#"${DOS_ROOT}/"}"   # strip leading DOS_ROOT if present
    DOS_PATH="${DOS_PATH^^}"                # uppercase (DOS convention)
    DOS_PATH="${DOS_PATH//\//\\}"           # forward → back slashes

    exec flatpak run "$DOSBOX_ID" \
        --conf "$STAGING_CFG" \
        -c "CD QBASIC" \
        -c "QBASIC.EXE /RUN C:\\${DOS_PATH}"
fi

exec flatpak run "$DOSBOX_ID" --conf "$QBASIC_CFG"
