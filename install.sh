#!/usr/bin/env bash
# Clinj CLI installer.
#   curl -fsSL https://raw.githubusercontent.com/AmirmLotfy/clinj/main/install.sh | bash
# Installs the (zero-dependency) engine and a `clinj` command on your PATH.
set -euo pipefail

REPO="https://github.com/AmirmLotfy/clinj"
SHARE="${HOME}/.local/share/clinj"
BINDIR="${HOME}/.local/bin"

echo "🧼 Installing Clinj CLI…"
mkdir -p "$SHARE" "$BINDIR"
if [[ -d "$SHARE/repo/.git" ]]; then
    git -C "$SHARE/repo" pull -q --ff-only
else
    git clone -q --depth 1 "$REPO" "$SHARE/repo"
fi
ln -sf "$SHARE/repo/bin/clinj" "$BINDIR/clinj"
chmod +x "$SHARE/repo/bin/clinj" "$SHARE/repo/core/clinj.sh"

echo "✅ Installed: $BINDIR/clinj"
case ":$PATH:" in
    *":$BINDIR:"*) echo "   Run:  clinj scan" ;;
    *) echo "   Add ~/.local/bin to your PATH, e.g.:"
       echo "     echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
       echo "   Then:  clinj scan" ;;
esac
