# Vitrum

**Vitrum** is a desktop environment for Linux that works the way people who grew
up on a PC expect: a taskbar with a Start button, a two‑column Start menu with
search, a notification area with a clock, snapping windows to the screen edges,
<kbd>Alt</kbd>+<kbd>Tab</kbd>, the Windows key, a file Explorer, a Settings app —
and double‑clicking a `.exe` just runs it.

It is its own design. The look takes after the glass desktops of 2009 (with
colourful frosted window frames), borrows conveniences from later releases (snap
layouts, a notification centre, quick settings, an optional centred taskbar) and
uses no Microsoft artwork, names or assets.

Vitrum is a single program: a **Wayland compositor and shell** written in C++
and Qt Quick. It draws every window frame itself, so applications get the same
title bar and buttons instead of each toolkit's own.

## Highlights

| | |
|---|---|
| **Themes** | **Aero** (tinted glass with blur and light streaks), **Modern** (flat, frosted, rounded corners, full‑height caption buttons), **Basic** (opaque, simple, light blue frames). Accent colour, colour intensity and transparency are adjustable. |
| **Taskbar** | Start orb, pinned + running apps combined per program, live window thumbnails with Peek, jump lists, drag to reorder pins, notification area (network, volume, battery, clock, notifications), "show desktop" strip. Optional centred layout and small buttons. |
| **Start menu** | Pinned and most‑used programs, *All Programs* folders, instant search over programs and settings, Run, places, Shut down menu. |
| **Windows** | Glass frames with min/max/close, double‑click to maximize, drag to edges to snap (halves, quarters, maximize), snap‑layouts flyout on the maximize button, Win+Arrow snapping, Alt+Tab with live previews, open/close/minimize animations. |
| **Windows programs** | `.exe`, `.msi`, `.bat`/`.cmd`, `.lnk`, `.reg`, `.vbs` open with a double‑click through a private, pre‑configured compatibility runtime (Wine) that is never shown: no Wine menus, branding, prompts or console output. Programs keep their own icons in Explorer and on the taskbar, and installed programs appear in the Start menu under *Windows Programs*. `.jar` files run with Java. |
| **Built‑in apps** | Explorer (navigation pane, breadcrumb address bar, icon/details views, copy/cut/paste, Recycle Bin, drives with usage bars), Settings, Notepad, Photo Viewer, Run, Task Manager, Properties, About. |
| **Notifications** | A freedesktop notification server: toasts above the clock, history and quick actions (Wi‑Fi, Focus assist, Night light, Transparency, Screenshot, Lock) in the Action Center. |
| **Session** | PAM lock screen (Win+L), Ctrl+Alt+Del options screen, power menu via logind, XDG autostart, Print Screen screenshots. |

### Keyboard shortcuts

| Keys | Action |
|---|---|
| <kbd>Win</kbd> | Open/close Start |
| <kbd>Win</kbd>+<kbd>D</kbd> / <kbd>M</kbd> | Show desktop / minimize all |
| <kbd>Win</kbd>+<kbd>E</kbd> | Explorer |
| <kbd>Win</kbd>+<kbd>R</kbd> | Run |
| <kbd>Win</kbd>+<kbd>I</kbd> | Settings |
| <kbd>Win</kbd>+<kbd>A</kbd> | Action Center |
| <kbd>Win</kbd>+<kbd>L</kbd> | Lock |
| <kbd>Win</kbd>+<kbd>X</kbd> | Quick links menu |
| <kbd>Win</kbd>+<kbd>←</kbd>/<kbd>→</kbd>/<kbd>↑</kbd>/<kbd>↓</kbd> | Snap left/right, maximize, restore/minimize |
| <kbd>Win</kbd>+<kbd>Z</kbd> | Snap layouts |
| <kbd>Win</kbd>+<kbd>1</kbd>…<kbd>9</kbd> | Open/switch to taskbar item |
| <kbd>Alt</kbd>+<kbd>Tab</kbd> | Switch windows |
| <kbd>Alt</kbd>+<kbd>F4</kbd> | Close window |
| <kbd>Ctrl</kbd>+<kbd>Shift</kbd>+<kbd>Esc</kbd> | Task Manager |
| <kbd>Ctrl</kbd>+<kbd>Alt</kbd>+<kbd>Del</kbd> | Options screen |
| <kbd>PrtScn</kbd> / <kbd>Alt</kbd>+<kbd>PrtScn</kbd> | Screenshot of the screen / active window |

## Try it

### Live ISO (recommended)

Every push builds a bootable live ISO (Debian 13 base) in GitHub Actions — open
the **Live ISO** workflow run and download the `vitrum-live-iso` artifact. Tagged
releases (`v*`) attach the ISO to the release.

Boot it in a VM with at least 4 GB RAM and 2 CPUs:

* **QEMU/KVM**: `qemu-system-x86_64 -enable-kvm -m 4096 -smp 2 -vga virtio -cdrom vitrum-*-live-amd64.iso`
* **VirtualBox**: Graphics controller *VMSVGA*, 128 MB video memory, EFI optional.
* **VMware**: default settings.

The live session logs in automatically (user `user`, password `live`) and starts
Vitrum on the first console. It drives the display through DRM/KMS and falls back
to a bare X server on virtual GPUs without KMS support.

### Run nested in your current desktop

```bash
vitrum --windowed 1366x768
```

### Install the package

CI publishes `.deb` packages for Ubuntu 24.04 and Debian 13. After installing,
pick **Vitrum** in your display manager's session list, or run `vitrum-session`
from a text console.

## Building

Requirements: CMake ≥ 3.22, a C++17 compiler, Qt ≥ 6.4 (Base, Declarative,
Wayland Compositor, ShaderTools, Svg, Qt5Compat), wayland-scanner and PAM.
On Ubuntu 24.04:

```bash
sudo apt install cmake ninja-build g++ libpam0g-dev libwayland-dev libwayland-bin qt6-base-dev qt6-declarative-dev qt6-wayland-dev qt6-shadertools-dev qt6-svg-dev qml6-module-qtwayland-compositor qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-qtquick-window qml6-module-qt5compat-graphicaleffects qml6-module-qt-labs-folderlistmodel
```

```bash
cmake -S . -B build -G Ninja && cmake --build build && ctest --test-dir build
```

`vitrum --demo DIR` runs a scripted tour of the shell, writes a screenshot of
each step to `DIR` and exits; add `--strict` to fail on any QML warning. CI runs
this under Xvfb with a real Wayland client and uploads the screenshots.

## Layout

```
src/            C++ backends exposed to QML as Vitrum.Core
                (apps, launcher, Windows compatibility, notifications, PAM,
                 system status, settings, shortcuts, file operations,
                 server-side decoration protocol)
qml/            The shell (module Vitrum)
  windows/      Window frame and caption buttons
  shell/        Taskbar, Start menu, flyouts, Action Center, Alt+Tab, lock screen…
  apps/         Explorer, Settings, Notepad, Photo Viewer, Run, Task Manager…
  components/   Glass surfaces, buttons, menus and other controls
shaders/        Glass and wallpaper shaders
icons/          Original SVG icon set
data/           Session launcher, file associations, PAM, portal config
iso/            Live ISO recipe (live-build)
tests/          Unit tests
```

## Status and limitations

This is an early release. Known gaps:

* **X11‑only applications** need XWayland, which Vitrum doesn't host yet. Most
  current apps (Qt, GTK, Firefox, Chromium, Electron with Ozone) are native
  Wayland. Windows programs use the compatibility runtime's native Wayland
  driver (Wine 9 or newer). **Java desktop (Swing/AWT) programs** are X11‑only
  and need XWayland; command‑line `.jar` files work.
* Applications that insist on drawing their own title bar (GTK 4 apps with
  header bars, some Electron apps) keep it; everything that supports server‑side
  decorations (Qt, GTK 3, Firefox, …) gets the Vitrum frame.
* Single monitor; no display‑settings UI for resolution yet.
* No system‑tray (StatusNotifierItem) icons from third‑party apps yet.

## License

GPL-3.0-or-later. `protocols/server-decoration.xml` is LGPL-2.1-or-later (KDE).
