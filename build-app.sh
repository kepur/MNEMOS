#!/bin/zsh
# Build "MNEMOS.app" from main.swift.
#   ./build-app.sh            build into ./build/
#   ./build-app.sh --install  also replace ~/Desktop/MNEMOS.app
#                             (the previous bundle is kept in ./backups/)
set -eu

src="${0:A:h}"
name="MNEMOS"
out="$src/build/$name.app"
target="$HOME/Desktop/$name.app"

rm -rf "$out"
mkdir -p "$out/Contents/MacOS" "$out/Contents/Resources"
swiftc -O -target arm64-apple-macos13.0 -framework AppKit "$src/main.swift" -o "$out/Contents/MacOS/MNEMOS"
cp "$src/Info.plist" "$out/Contents/Info.plist"
cp "$src/AppIcon.icns" "$out/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$out" >/dev/null
echo "built $out ($(defaults read "$out/Contents/Info.plist" CFBundleShortVersionString))"

if [[ "${1:-}" == "--install" ]]; then
  pkill -TERM -f "$name.app/Contents/MacOS/MNEMOS" 2>/dev/null || true
  pkill -TERM -f "Codex Model Switcher.app" 2>/dev/null || true
  pkill -TERM -f "CodexModelSwitcher" 2>/dev/null || true
  for _ in {1..20}; do pgrep -f "$name.app/Contents/MacOS" >/dev/null || break; sleep 0.25; done
  if [[ -d "$target" ]]; then
    mkdir -p "$src/backups"
    ditto "$target" "$src/backups/$name-$(defaults read "$target/Contents/Info.plist" CFBundleShortVersionString)-$(date +%Y%m%d-%H%M%S).app"
    rm -rf "$target"
  fi
  if [[ -d "$HOME/Desktop/Codex Model Switcher.app" ]]; then
    mkdir -p "$src/backups"
    ditto "$HOME/Desktop/Codex Model Switcher.app" "$src/backups/CodexModelSwitcher-$(date +%Y%m%d-%H%M%S).app"
    rm -rf "$HOME/Desktop/Codex Model Switcher.app"
  fi
  ditto "$out" "$target"
  echo "installed $target"
fi
