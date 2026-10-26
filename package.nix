{ lib, writeShellApplication, quickshell, grim, imagemagick, tesseract, zbar, wf-recorder, wl-clipboard, jq
, ocrLanguages ? [ "eng" "fra" ]
}:

# Wraps the QuickShell config in a single command:
#   capture daemon            -> runs the daemon (exec-once)
#   capture                   -> freezes the screens and opens the overlay
#   capture text              -> same overlay, the selection is copied as text
#   capture screen            -> saves the focused monitor, no overlay
#   capture record [--audio]  -> starts or stops recording the focused monitor
# hyprctl is taken from the session's PATH so it always matches the running Hyprland.
writeShellApplication {
  name = "capture";
  runtimeInputs = [
    quickshell grim imagemagick zbar wf-recorder wl-clipboard jq
    (tesseract.override { enableLanguages = ocrLanguages; })
  ];
  text = ''
    config=${./config}
    state="''${XDG_RUNTIME_DIR:-/tmp}/capture"

    export CAPTURE_OCR_LANGS=${lib.concatStringsSep "+" ocrLanguages}
    export CAPTURE_SCREENSHOT_DIR="''${CAPTURE_SCREENSHOT_DIR:-$HOME/Pictures/Screenshots}"
    export CAPTURE_SCREENCAST_DIR="''${CAPTURE_SCREENCAST_DIR:-$HOME/Videos/Screencasts}"

    ipc() { quickshell --path "$config" ipc call "$@"; }
    focused() { hyprctl monitors -j | jq -r '.[] | select(.focused) | .name'; }

    # Grabs every monitor at once, with Hyprland's layout at that instant, so the
    # overlay shows (and crops) exactly what was on screen at the keypress.
    freeze() {
      rm -rf "$state/frames"
      frame="$state/frames/$(date +%s%N)"
      mkdir -p "$frame"
      monitors=$(hyprctl monitors -j)
      for name in $(jq -r '.[].name' <<<"$monitors"); do
        grim -o "$name" "$frame/$name.png" &
      done
      printf '{"monitors":%s,"clients":%s,"cursor":%s,"rounding":%s}' "$monitors" "$(hyprctl clients -j)" \
        "$(hyprctl cursorpos -j)" "$(hyprctl getoption decoration:rounding -j | jq .int)" > "$frame/layout.json"
      wait
    }

    case "''${1:-}" in
      daemon)
        mkdir -p "$state"
        exec quickshell --path "$config" --no-duplicate ;;
      "")
        freeze
        ipc capture open "$frame" ;;
      text)
        freeze
        ipc capture text "$frame" ;;
      screen)
        out="$CAPTURE_SCREENSHOT_DIR/$(date +%Y-%m-%d_%H-%M-%S).png"
        mkdir -p "$CAPTURE_SCREENSHOT_DIR"
        grim -o "$(focused)" "$out"
        wl-copy --type image/png < "$out" ;;
      record)
        audio=false
        [ "''${2:-}" = "--audio" ] && audio=true
        ipc record toggle "$(focused)" "$audio" ;;
      *)
        echo "usage: capture [daemon | text | screen | record [--audio]]" >&2
        exit 1 ;;
    esac
  '';
}
