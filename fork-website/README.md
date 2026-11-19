# Snowy fork website

The website for this fork of Snowy. It began as a copy of the original site in [`../website`](../website) by Yaroslav Solovev (MIT) and keeps its playable desktop: movable windows, a Dock, and snow you can push around.

## What is different from `../website`

- **Thaw.** `src/snow-engine.js` has `beginThaw()`, the same straight-line melt as the Mac app’s Thaw Settled Snow. Visitors can start it from the menu bar, the About window, the Weather window, or the Terminal (`thaw`).
- **Links and credit.** Download and source links point at this fork. The About window and the “about this copy.txt” note credit the original and link to it.
- **No payments.** The price sheet, wish list, Polar checkout, Cloudflare Worker, Windows downloads and seasonal sound are removed. The site is static files with no packages to install.

`../website` is left exactly as the original ships it, so pulling from upstream never conflicts with this folder. Its [design notes](../website/docs/design.md) explain the look that this copy inherits.

## Run, test, build

Needs **Node.js 22 or later**.

```sh
npm --prefix fork-website run dev      # http://127.0.0.1:4174
npm --prefix fork-website test         # engine, geometry, preference and download tests
npm --prefix fork-website run build    # static site in fork-website/dist
```

`npm --prefix fork-website run test:browser` drives the running dev server in a temporary headless Chrome profile and checks the desktop, phone, Reduced Motion, download and thaw flows.

## Publish

The site is the Vercel project `snowy-thaw`, live at <https://snowy-thaw.vercel.app>. It is published from this folder with the CLI, not from GitHub:

```sh
vercel deploy --cwd fork-website --prod
```

[`vercel.json`](vercel.json) runs the build, serves `dist`, and sets the same security headers the page declares.

## Downloads and updates

`#download` in [`index.html`](index.html) saves [`downloads/Snowy-macOS-arm64.dmg`](downloads), which the site serves itself. A click also shows how to install it and what to do when macOS blocks a build that Apple has not notarized.

The same folder is this fork’s update feed. `App/Info.plist` points `SUFeedURL` at `https://snowy-thaw.vercel.app/downloads/appcast.xml`, and installed copies check it and offer **Update** in the snowflake menu when it lists a newer build. The feed and the update archive are signed with this fork’s own key; the app carries the public half as `SUPublicEDKey`.

To ship a new version:

1. Raise `CFBundleShortVersionString` and `CFBundleVersion` in `App/Info.plist`. Installed copies only see an update with a higher `CFBundleVersion`.
2. Run `./fork-website/scripts/publish-download.sh` from the repository root. It rebuilds the app, packages it, signs the feed, checks both signatures, and replaces the three files in `downloads/`.
3. Run `npm --prefix fork-website test`, then publish with `vercel deploy --cwd fork-website --prod`.

The private signing key lives in the login Keychain of the Mac that created it, under the Sparkle account `snowy-fork`. Keep a backup somewhere safe (`generate_keys --account snowy-fork -x <file>` exports it). If it is lost, installed copies can never accept another update and everyone has to download the app again.

The web address is part of every installed copy, so keep the `snowy-thaw` Vercel project serving `/downloads/appcast.xml` even if the site later moves to another domain.
