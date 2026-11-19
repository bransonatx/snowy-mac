import test from "node:test";
import assert from "node:assert/strict";
import { open, readFile, stat } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

test("the Download button points at a disk image this site ships", async () => {
  const page = await readFile(resolve(root, "index.html"), "utf8");
  const link = page.match(/<a\s+id="download"[^>]*>/)?.[0] ?? "";
  const href = link.match(/href="([^"]+)"/)?.[1];
  assert.equal(href, "./downloads/Snowy-macOS-arm64.dmg");
  assert.match(link, /\sdownload[\s>]/, "the link saves the file");

  const file = resolve(root, href);
  const { size } = await stat(file);
  assert.ok(size > 1_000_000, `disk image looks too small: ${size} bytes`);
  // Every UDIF disk image ends with a 512-byte trailer that starts with "koly".
  const handle = await open(file);
  const { buffer } = await handle.read(Buffer.alloc(4), 0, 4, size - 512);
  await handle.close();
  assert.equal(buffer.toString("latin1"), "koly");

  const build = await readFile(resolve(root, "scripts/build.mjs"), "utf8");
  assert.match(build, /"downloads"/, "the build copies the disk image");
});

test("the update feed on the site describes the app in this repository", async () => {
  const site = "https://snowy-thaw.vercel.app/downloads/";
  const plist = await readFile(resolve(root, "../App/Info.plist"), "utf8");
  const setting = (key) =>
    plist.match(new RegExp(`<key>${key}</key><string>([^<]*)</string>`))?.[1];
  assert.equal(setting("SUFeedURL"), site + "appcast.xml");
  assert.ok(setting("SUPublicEDKey"), "the app carries a public key for its updates");

  const feed = await readFile(resolve(root, "downloads/appcast.xml"), "utf8");
  assert.equal(feed.match(/<item>/g)?.length, 1, "the feed lists one release");
  assert.equal(
    feed.match(/<sparkle:shortVersionString>([^<]*)</)?.[1],
    setting("CFBundleShortVersionString"),
    "run fork-website/scripts/publish-download.sh after changing the app version",
  );
  assert.equal(feed.match(/<sparkle:version>([^<]*)</)?.[1], setting("CFBundleVersion"));
  const enclosure = feed.match(/<enclosure [^>]*>/)?.[0] ?? "";
  assert.equal(enclosure.match(/url="([^"]*)"/)?.[1], site + "Snowy-macOS-arm64.zip");
  const archive = await stat(resolve(root, "downloads/Snowy-macOS-arm64.zip"));
  assert.equal(Number(enclosure.match(/length="(\d+)"/)?.[1]), archive.size);
  assert.match(enclosure, /sparkle:edSignature="[A-Za-z0-9+\/=]{80,}"/);
  // The app sets SURequireSignedFeed, so an unsigned feed would be ignored.
  assert.match(feed, /<!-- sparkle-signatures:/);
});
