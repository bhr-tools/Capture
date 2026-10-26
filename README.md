# Capture

Screenshots, screen recording and on-screen text selection for Hyprland, built
on QuickShell.

- **Overlay**: the screens are frozen at the keypress. Hovering highlights the
  window under the pointer: click to capture it, drag to capture an area, `F`
  for the whole monitor (or `Enter` for what is highlighted). The image is
  saved to `~/Pictures/Screenshots` and copied to the clipboard. A window
  keeps its rounded corners (transparent), without Hyprland's border.
- **Live Text**: `T` in the overlay, then drag an area (or click a window, `F`
  for the whole monitor): only that area is read, so a selection never runs
  outside of it. Drag inside it to select, double-click for a word, `Ctrl+A`
  for everything, `Ctrl+C` or `Enter` to copy (the whole area without a
  selection). A drag outside picks a new area.
- **Text capture**: `capture text` opens the same overlay, but the area or
  window is read and its text copied directly. A QR code is copied instead
  when there is one.
- **Recording**: `capture record` records the focused monitor to
  `~/Videos/Screencasts` (`--audio` adds the microphone). Run it again to
  stop: the file is then copied to the clipboard (as a `file://` URI).

`Esc` or right click closes the overlay. Nothing is captured or recorded
from the overlay itself: every image is cropped from the frozen frame.

## Commands

```sh
capture daemon             # daemon (exec-once)
capture                    # overlay
capture text               # overlay, the selection is copied as text
capture screen             # focused monitor, no overlay
capture record [--audio]   # starts or stops recording the focused monitor
```

While recording, `$XDG_RUNTIME_DIR/capture/recording` holds the path of the
video (it is empty otherwise), for a bar to show it.

`CAPTURE_SCREENSHOT_DIR` and `CAPTURE_SCREENCAST_DIR` override the output
folders.

## Installation (home-manager)

```nix
inputs.capture.url = "path:/home/ben/Dev/Capture";

# home.nix
imports = [ inputs.capture.homeManagerModules.default ];
programs.capture = {
  enable = true;                        # installs it and adds exec-once
  ocrLanguages = [ "eng" "fra" ];       # Tesseract languages
};
```

```ini
# hyprland
bind = SUPER SHIFT, S, exec, capture
bind = , Print, exec, capture
bind = SUPER CONTROL, S, exec, capture screen
bind = SUPER SHIFT, T, exec, capture text
bind = SUPER SHIFT, R, exec, capture record
```

## Development

```sh
nix develop
quickshell -p ./config                 # live-reloads on save
```

The overlay needs a frame written by the wrapper (`freeze` in `package.nix`),
so the simplest is `nix build` then `./result/bin/capture daemon`.
