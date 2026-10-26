pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Rosé Pine palettes and metrics, mirroring the Theme.qml of the
// Nixos-Workstations bar. The variant follows ~/.config/theme_state, written
// by theme-switch, so a theme change applies live.
Singleton {
    id: root

    property bool dark: true

    // --- Palette ---

    readonly property color base: dark ? "#191724" : "#faf4ed"
    readonly property color surface: dark ? "#1f1d2e" : "#fffaf3"
    readonly property color overlay: dark ? "#26233a" : "#f2e9e1"
    readonly property color muted: dark ? "#6e6a86" : "#9893a5"
    readonly property color subtle: dark ? "#908caa" : "#797593"
    readonly property color text: dark ? "#e0def4" : "#575279"
    readonly property color love: dark ? "#eb6f92" : "#b4637a"
    readonly property color gold: dark ? "#f6c177" : "#ea9d34"
    readonly property color pine: dark ? "#31748f" : "#286983"
    readonly property color foam: dark ? "#9ccfd8" : "#56949f"
    readonly property color iris: dark ? "#c4a7e7" : "#907aa9"
    readonly property color highlightLow: dark ? "#21202e" : "#f4ede8"
    readonly property color highlightMed: dark ? "#403d52" : "#dfdad9"
    readonly property color highlightHigh: dark ? "#524f67" : "#cecacd"

    readonly property color accent: pine


    // --- Typography ---

    readonly property string font: "Inter"
    readonly property int fontSize: 13
    readonly property int smallSize: 11
    readonly property int titleSize: 15


    // --- Metrics ---

    // Matches Hyprland's gaps_out and rounding.
    readonly property int gap: 5
    readonly property int radius: 7
    readonly property int padding: 12
    readonly property int spacing: 8
    readonly property int anim: 120


    FileView {
        path: Quickshell.env("HOME") + "/.config/theme_state"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.dark = text().trim() !== "light"
    }
}
