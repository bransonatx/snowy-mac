#!/bin/zsh
# Copy the packaged DMG next to the Seasons website so the page's download button works.
set -euo pipefail
project_root="${0:A:h:h}"
dmg="$project_root/build/releases/Seasons-macOS-arm64.dmg"
if [[ ! -f "$dmg" ]]; then
  print -u2 "Missing ${dmg:t}. Run ./scripts/package-release.sh first."
  exit 1
fi
cp "$dmg" "$project_root/site/${dmg:t}"
print "Staged ${dmg:t} in site/ ($(du -h "$dmg" | cut -f1 | tr -d ' '))."
