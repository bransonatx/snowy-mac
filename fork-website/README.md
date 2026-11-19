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

The folder is ready for Vercel: set the project’s **Root Directory** to `fork-website`. [`vercel.json`](vercel.json) runs the build, serves `dist`, and sets the same security headers the page declares.

## The download button

`#download` in [`index.html`](index.html) saves [`downloads/Snowy-macOS-arm64.dmg`](downloads), which the site serves itself. A click also shows how to install it and what to do when macOS blocks a build that Apple has not notarized.

The disk image is a built copy of this fork’s app, committed here so the site needs nothing else. After changing the app, rebuild it and replace the file from the repository root:

```sh
./scripts/package-release.sh
cp build/releases/Snowy-macOS-arm64.dmg fork-website/downloads/
```
