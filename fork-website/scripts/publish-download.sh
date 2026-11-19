#!/bin/zsh
# Rebuilds this fork's Mac app and refreshes everything the website serves for it:
# the disk image, the update archive, and the signed update feed.
#
# When the app has changed, raise CFBundleShortVersionString and CFBundleVersion in
# App/Info.plist first. Installed copies only see an update with a higher CFBundleVersion.
set -euo pipefail

site_root="${0:A:h:h}"
project_root="${site_root:h}"
site_url="https://snowy-thaw.vercel.app"
key_account="snowy-fork"
downloads="$site_root/downloads"
release_dir="$project_root/build/releases"
sparkle_bin="$project_root/.build/artifacts/sparkle/Sparkle/bin"
dmg_name="Snowy-macOS-arm64.dmg"
zip_name="Snowy-macOS-arm64.zip"

mode="${1:-}"
if [[ $# -gt 1 || ($# -eq 1 && "$mode" != "--skip-build") ]]; then
  print -u2 "Usage: ./fork-website/scripts/publish-download.sh [--skip-build]"
  exit 2
fi

feed_url="$site_url/downloads/appcast.xml"
if [[ "$(plutil -extract SUFeedURL raw "$project_root/App/Info.plist" 2>/dev/null || true)" != "$feed_url" ]]; then
  print -u2 "App/Info.plist must set SUFeedURL to $feed_url."
  exit 1
fi
if [[ -L "$downloads" || ! -d "$downloads" ]]; then
  print -u2 "Missing fork-website/downloads."
  exit 1
fi

cd "$project_root"
if [[ "$mode" == "--skip-build" ]]; then
  ./scripts/package-release.sh --skip-build
else
  ./scripts/package-release.sh
fi

for tool in generate_keys generate_appcast sign_update; do
  if [[ ! -x "$sparkle_bin/$tool" ]]; then
    print -u2 "Build Snowy to resolve its pinned Sparkle release tools."
    exit 1
  fi
done

app_plist="$project_root/build/Snowy.app/Contents/Info.plist"
public_key="$("$sparkle_bin/generate_keys" --account "$key_account" -p)"
if [[ "$(plutil -extract SUPublicEDKey raw "$app_plist")" != "$public_key" ]]; then
  print -u2 "The built app does not carry the public half of the '$key_account' signing key."
  exit 1
fi
version="$(plutil -extract CFBundleShortVersionString raw "$app_plist")"

staging_dir="$(mktemp -d "$release_dir/.Snowy-site.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
mkdir "$staging_dir/feed"
cp "$release_dir/$zip_name" "$staging_dir/feed/$zip_name"

# The private key leaves the login Keychain only for this run, readable by this user alone,
# in a directory that is removed on exit.
(umask 077 && "$sparkle_bin/generate_keys" --account "$key_account" -x "$staging_dir/key" > /dev/null)
"$sparkle_bin/generate_appcast" --ed-key-file "$staging_dir/key" --maximum-deltas 0 \
  --download-url-prefix "$site_url/downloads/" --link "$site_url/" \
  -o "$staging_dir/feed/appcast.xml" "$staging_dir/feed"

signature="$(python3 - "$staging_dir/feed/appcast.xml" "$staging_dir/feed/$zip_name" "$site_url/downloads/" "$version" <<'PY'
import base64
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

feed, archive, base_url, version = sys.argv[1:]
archive = Path(archive)
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
items = ET.parse(feed).findall("./channel/item")
if len(items) != 1:
    raise SystemExit("Expected a single release in the appcast.")
item = items[0]
enclosure = item.find("enclosure")
signature = enclosure.get("{" + ns["sparkle"] + "}edSignature", "")
if (item.findtext("sparkle:shortVersionString", namespaces=ns) != version
        or enclosure.get("url") != base_url + archive.name
        or enclosure.get("length") != str(archive.stat().st_size)
        or len(base64.b64decode(signature, validate=True)) != 64):
    raise SystemExit("Appcast does not match the packaged archive and app version.")
print(signature)
PY
)"
# The app requires a signed feed and a signed archive; check both before anything is replaced.
"$sparkle_bin/sign_update" --verify --ed-key-file "$staging_dir/key" "$staging_dir/feed/$zip_name" "$signature"
"$sparkle_bin/sign_update" --verify --ed-key-file "$staging_dir/key" "$staging_dir/feed/appcast.xml"
rm -f "$staging_dir/key"

cp "$release_dir/$dmg_name" "$downloads/$dmg_name"
cp "$staging_dir/feed/$zip_name" "$downloads/$zip_name"
cp "$staging_dir/feed/appcast.xml" "$downloads/appcast.xml"
print "Site downloads now hold Snowy $version: $dmg_name, $zip_name and a signed appcast.xml."
print "Publish them with: vercel deploy --cwd fork-website --prod"
