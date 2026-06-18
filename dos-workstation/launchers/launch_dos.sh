#!/usr/bin/env bash
# launch_dos.sh — Launch the DOS workspace in DOSBox Staging
#
# Add this script as a non-Steam game in Steam Desktop Mode:
#   Games → Add a Non-Steam Game → Browse → select this file
# Then apply the recommended Steam Input layout for controller support.

DOSBOX_ID="io.github.dosbox-staging"
CFG="${HOME}/.var/app/${DOSBOX_ID}/config/dosbox/dosbox-staging.conf"

if ! flatpak list --user 2>/dev/null | grep -q "$DOSBOX_ID" && \
   ! flatpak list        2>/dev/null | grep -q "$DOSBOX_ID"; then
    echo "DOSBox Staging is not installed."
    echo "Run setup.sh first, or install manually:"
    echo "  flatpak install --user flathub ${DOSBOX_ID}"
    exit 1
fi

if [[ ! -f "$CFG" ]]; then
    echo "Config not found: $CFG"
    echo "Run setup.sh to deploy the configuration."
    exit 1
fi

exec flatpak run "$DOSBOX_ID" --conf "$CFG"
