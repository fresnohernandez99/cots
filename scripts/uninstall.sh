#!/bin/bash
# Same as Ajustes → Desinstalar. Pass --delete-notes to also send the notes to the Trash.
set -euo pipefail
for APP in "/Applications/coTs.app" "$HOME/Applications/coTs.app"; do
    if [ -d "$APP" ]; then
        pkill -x coTs 2>/dev/null || true
        "$APP/Contents/MacOS/coTs" --uninstall "$@"
        echo "Desinstalado: $APP"
        exit 0
    fi
done
echo "coTs no está instalada en /Applications ni en ~/Applications"
