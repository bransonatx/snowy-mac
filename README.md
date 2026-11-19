# Snowy ❄️

Snow for your desktop. A native Mac app that lets winter settle on your windows, widgets, and bottom Dock.

Sweep a pile with your pointer. Pick up a shovel. Make a little mess.

![An illustrated Snowy desktop with snow resting on overlapping windows and a bottom Dock](docs/snowy.svg)

## Get it

Download the latest [Apple Silicon DMG](https://github.com/soloiaros/snowy-mac/releases/latest/download/Snowy-macOS-arm64.dmg), open it, and drag **Snowy.app** onto **Applications**. Eject the disk image, then open Snowy from Applications. On a fresh setup, three quick pages show how to sweep snow, adjust wind, and find the menu-bar controls. Skip or close the walkthrough at any time; it won’t reopen on later launches.

Requires **macOS 14 or later**. The current download is for Apple Silicon. Intel Macs can build from source. The 0.10.0 beta is signed locally and can trigger Gatekeeper’s malware-verification warning. If macOS blocks the copy you downloaded here, go to **System Settings → Privacy & Security → Open Anyway** after trying to open it.

When a compatible release is available, **Update** appears in blue near the bottom of the snowflake menu. Click it to download, install, and reopen Snowy. To upgrade from 0.9.1 or earlier, quit Snowy and replace it in Applications using the DMG once.

## Let it snow

Click the snowflake in your menu bar to make yourself comfortable:

- Choose **Light**, **Steady**, or **Flurry**.
- Brush snow away with the **Glove**, or choose **Shovel** for a proper clear-out.
- Open **Wind…** and stretch or rotate the arrow to change its strength and direction.
- **Pause** the weather or **Clear Settled Snow** whenever you like.
- Choose **Thaw Settled Snow** to let it melt away over a few seconds instead. New snow waits until the thaw is done. With Reduced Motion on, it clears at once.

Snow collects on window tops, widgets, Spotlight, and a bottom-positioned Dock. Moving windows push it around; closing Spotlight lets its uncovered snow fall. Side-positioned Docks are intentionally left out.

Choose **Open Snowy…** in the snowflake menu to apply a wallpaper, select a pixel-art preset, or build your own desktop scene. Props catch snow and can slide when swept. In **Edit Scene**, place individual pieces and attach string lights to the desktop edges and widgets. Finder icon anchors are optional and require Accessibility access. The **Guide** includes **Replay Walkthrough**.

The desktop stays clickable. Snowy reads public window bounds for snow and widgets. Finder icon anchors use Accessibility only when enabled. Snowy keeps your settings and imported wallpapers on your Mac and checks GitHub for signed updates.

## Seasons

This branch builds a second, separate app called **Seasons** (`build/Seasons.app`, app ID `app.seasons.desktop`). It keeps its own settings and wallpapers, so it can sit next to the original snow-only Snowy without the two sharing anything. The `my-snowy` branch still builds `build/Snowy.app`.

Seasons adds a second season to Snowy's winter. From the September equinox to the December solstice the snowflake becomes a leaf and leaves fall instead of snow; **Season** in the menu overrides the calendar.

- Leaves pile up on the same windows, widgets, Dock, and floor as snow, and ride a dragged window the same way.
- Leaves are light. Sweeping a pile with the **Glove** or **Rake**, or ploughing a window through it, sends its leaves into the air to settle wherever they land.
- **Cursor Tool → Leaf Blower** works from a distance: sweep the pointer past a pile and it lifts off along your pass. A faster pass lifts more.
- Every so often a gust carries a few settled leaves away.
- Colour follows the date, from yellow-green in September to red and brown by December.
- **Open Seasons…** leads with the season on the desktop. In fall that is the autumn wallpapers (Golden Hour, Harvest Moon) and the autumn decoration layouts (Pumpkin Patch, Maple Grove, Cider Stand, Woodland Cabin); the winter ones stay available underneath. String lights also come in a Harvest palette.

Winter is unchanged. Switching season clears what has settled. In-app updates are turned off in Seasons so it does not replace itself with Snowy's releases.

### Seasons installer and website

`swift run Snowy --art out.png` draws every decoration piece and starter wallpaper on one sheet, for checking new artwork without opening the app.

`./scripts/package-release.sh` packages `build/Seasons.app` into `build/releases/Seasons-macOS-arm64.dmg`. The build is signed locally and not notarized, so a Mac that downloads it asks for **System Settings → Privacy & Security → Open Anyway** on first launch.

`site/` is the Seasons website: a small desktop where leaves fall and pile on the page's own windows, with the download in the middle. It is plain HTML, CSS and JavaScript with no build step. `./scripts/stage-site.sh` copies the DMG into `site/` (it is not committed). The `website/` folder is still upstream Snowy's site and is not used by Seasons.

## Build it yourself

You’ll need **Xcode 16 or later**, its Metal toolchain, and a Mac.

```sh
git clone https://github.com/soloiaros/snowy-mac.git
cd snowy-mac
./scripts/build-app.sh
open build/Snowy.app
```

The build script compiles the app and shaders, adds a local signature, and leaves the app in `build/`. It does not launch or install anything. If Xcode reports a missing Metal toolchain, install it from Xcode’s component settings first.

## Windows 11 beta

Choose [Windows Beta](https://snowy.aauburn.com/#download-windows) for x64 or ARM64. Open the setup file and follow the installer. Snowy lives in the system tray near the clock. The beta is unsigned, so Windows SmartScreen may warn or block it. [Windows build and update instructions](windows/README.md)

## A desktop in your browser

The [website](https://snowy.aauburn.com) has its own movable windows, a bottom Dock, and snow you can push around. There may also be someone thawing out for December. All downloads are pay what you want, including $0. Optional support uses [Polar hosted checkout](website/docs/payments.md).

Run it locally with **Node.js 22 or later**. No packages need installing.

```sh
npm --prefix website run dev
```

Open the address printed by the server. To make the static site, run `npm --prefix website run build`; the result goes into `website/dist/`. See the [Cloudflare deployment guide](website/docs/deployment.md) to publish it.

## A few rough edges

Window corners and some Dock bounds are estimates because macOS doesn’t expose every visible outline. Custom window shapes and system updates can need adjustments. The app has bounded simulation and rendering budgets, respects Low Power Mode and Reduced Motion, and pauses for sleep or fullscreen content. These are design choices, not a battery-life claim.

If something behaves oddly, [open an issue](https://github.com/soloiaros/snowy-mac/issues) with your macOS version, screen setup, Dock position, and steps to reproduce it.

## Contributing

```sh
swift test
npm --prefix website ci --ignore-scripts
npm --prefix website test
npm --prefix website run build
```

The tests run headlessly. They don’t open the app, inspect your desktop, or run benchmarks. See [CONTRIBUTING.md](CONTRIBUTING.md) for the project layout and release steps, and [the architecture notes](docs/architecture.md) for the physics and resource limits.

## Credits and license

This is a fork of [Snowy](https://github.com/soloiaros/snowy-mac), created by Yaroslav Solovev ([soloiaros](https://github.com/soloiaros)). The app, its physics, rendering, and artwork are the original author’s work. This fork adds **Thaw Settled Snow**.

The readable, personal repository style was inspired by [Window Sweaters](https://github.com/saragordic/window-sweaters). Snowy has its own implementation and artwork; it does not include Window Sweaters or JankyBorders code.

Code and original artwork use the [MIT license](LICENSE). The user-provided sound clip is excluded from that license.
