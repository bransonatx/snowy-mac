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
