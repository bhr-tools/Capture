pragma ComponentBehavior: Bound

import qs.common
import qs.services
import Quickshell
import Quickshell.Wayland
import QtQuick

// One monitor of the frozen frame. The window under the pointer (or the whole
// monitor) is highlighted: a click captures it, a drag captures an area. In
// Live Text mode the same gestures pick an area to read, then its words are
// selected like text.
PanelWindow {
    id: root

    required property ShellScreen modelData

    readonly property string name: modelData.name
    readonly property var monitor: Capture.monitors.find(m => m.name === name) ?? null
    readonly property bool hovered: Capture.hovered === name
    // Physical pixels per logical pixel, measured on the frozen image itself.
    readonly property real ratio: frozen.implicitWidth > 0 ? frozen.implicitWidth / canvas.width : 1
    readonly property rect screenRect: Qt.rect(0, 0, canvas.width, canvas.height)

    // Windows shown on this monitor, topmost first, in local coordinates:
    // special workspace, then floating, then by focus history. Their corners
    // are rounded like Hyprland draws them, except in fullscreen.
    readonly property var windows: {
        const m = monitor;
        if (!m)
            return [];
        const workspaces = [m.activeWorkspace.id, m.specialWorkspace.id].filter(id => id !== 0);
        const rank = c => c.workspace.id < 0 ? 0 : c.floating || c.pinned ? 1 : 2;
        return Capture.clients
            .filter(c => c.pinned ? c.monitor === m.id : workspaces.includes(c.workspace.id))
            .sort((a, b) => rank(a) - rank(b) || a.focusHistoryID - b.focusHistoryID)
            .map(c => {
                const x = Math.max(c.at[0] - m.x, 0);
                const y = Math.max(c.at[1] - m.y, 0);
                const right = Math.min(c.at[0] - m.x + c.size[0], canvas.width);
                const bottom = Math.min(c.at[1] - m.y + c.size[1], canvas.height);
                return { rect: Qt.rect(x, y, right - x, bottom - y), radius: c.fullscreen ? 0 : Capture.rounding };
            })
            .filter(w => w.rect.width > 0 && w.rect.height > 0);
    }

    // Starts where the cursor was at the keypress, before any motion.
    property point pointer: monitor ? Qt.point(Capture.cursor.x - monitor.x, Capture.cursor.y - monitor.y) : Qt.point(-1, -1)
    property point pressPoint
    property bool dragging: false
    readonly property rect dragRect: Qt.rect(Math.min(pressPoint.x, pointer.x), Math.min(pressPoint.y, pointer.y),
                                             Math.abs(pointer.x - pressPoint.x), Math.abs(pointer.y - pressPoint.y))
    // What a release captures: the dragged area, else the window under the
    // pointer, else the whole monitor.
    readonly property var pointedWindow: dragging ? null : windows.find(w => contains(w.rect, pointer)) ?? null
    readonly property rect target: dragging ? dragRect : pointedWindow?.rect ?? screenRect
    readonly property real targetRadius: pointedWindow?.radius ?? 0

    // Live Text area and its words, in local coordinates.
    readonly property bool zoneHere: Capture.textMode && Capture.zone?.monitor === name
    readonly property rect zoneRect: zoneHere ? Qt.rect(Capture.zone.x / ratio, Capture.zone.y / ratio,
                                                        Capture.zone.w / ratio, Capture.zone.h / ratio) : Qt.rect(0, 0, 0, 0)
    readonly property var words: zoneHere ? (Capture.zoneWords ?? []).map(w => ({
        x: w.x / ratio, y: w.y / ratio, w: w.w / ratio, h: w.h / ratio,
        text: w.text, line: w.line, par: w.par
    })) : []
    // A press inside the area selects words, anywhere else it picks a new area.
    property bool selecting: false
    // Highlighted: the area being picked, else the one being read.
    readonly property bool showZone: zoneHere && (selecting || !dragging)
    readonly property rect spot: showZone ? zoneRect : target
    property int anchorIndex: -1
    property int focusIndex: -1
    readonly property bool hasSelection: Capture.selectionMonitor === name && Capture.selection !== ""
    readonly property int selectionStart: Math.min(anchorIndex, focusIndex)
    readonly property int selectionEnd: Math.max(anchorIndex, focusIndex)
    // A double click also releases: its selection must survive that release.
    property bool keepSelection: false

    readonly property string hint: {
        if (Capture.textOnly)
            return "Drag: area   ·   Click: window   ·   F: screen   ·   Esc";
        if (!Capture.textMode)
            return "Drag: area   ·   Click: window   ·   F: screen   ·   T: text   ·   Esc";
        if (!zoneHere)
            return "Drag: area to read   ·   Click: window   ·   F: screen   ·   T: back   ·   Esc";
        if (!Capture.zoneWords)
            return "Reading text…";
        if (words.length === 0)
            return "No text found   ·   Drag: another area   ·   T: back";
        return "Drag: select   ·   Double-click: word   ·   Ctrl+A: all   ·   Ctrl+C: copy   ·   Drag outside: new area";
    }

    function contains(r: rect, p: point): bool {
        return p.x >= r.x && p.x < r.x + r.width && p.y >= r.y && p.y < r.y + r.height;
    }

    // Converts a local rectangle to image pixels and hands it to Capture: it is
    // captured, or read in Live Text mode.
    function grab(r: rect, radius: real): void {
        const max = (v, size) => Math.max(0, Math.min(Math.round(v * ratio), size));
        const x = max(r.x, frozen.implicitWidth);
        const y = max(r.y, frozen.implicitHeight);
        const w = max(r.x + r.width, frozen.implicitWidth) - x;
        const h = max(r.y + r.height, frozen.implicitHeight) - y;
        if (w <= 0 || h <= 0)
            return;
        if (Capture.textMode)
            Capture.readZone(name, { x: x, y: y, w: w, h: h });
        else
            Capture.capture(name, { x: x, y: y, w: w, h: h, radius: Math.round(radius * ratio) });
    }

    // The word under p, or -1.
    function wordAt(p: point): int {
        return words.findIndex(w => p.x >= w.x - 3 && p.x <= w.x + w.w + 3 && p.y >= w.y - 3 && p.y <= w.y + w.h + 3);
    }

    // The closest word to p, vertical distance counting more so a drag stays
    // on its line.
    function nearestWord(p: point): int {
        let best = -1;
        let bestDistance = Infinity;
        words.forEach((w, i) => {
            const dx = Math.max(w.x - p.x, 0, p.x - w.x - w.w);
            const dy = Math.max(w.y - p.y, 0, p.y - w.y - w.h);
            const distance = dx + 4 * dy;
            if (distance < bestDistance) {
                best = i;
                bestDistance = distance;
            }
        });
        return best;
    }

    function select(from: int, to: int): void {
        if (from < 0 || to < 0)
            return;
        anchorIndex = from;
        focusIndex = to;
        Capture.select(name, Capture.join(words, selectionStart, selectionEnd));
    }

    screen: modelData
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "black"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "capture"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Connections {
        target: Capture

        function onRequested(monitor: string, action: string): void {
            if (monitor !== root.name)
                return;
            if (action === "target")
                root.grab(root.target, root.targetRadius);
            else if (action === "screen")
                root.grab(root.screenRect, 0);
            else if (action === "all")
                root.select(0, root.words.length - 1);
        }
    }

    Item {
        id: canvas

        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            const ctrl = event.modifiers & Qt.ControlModifier;
            const enter = event.key === Qt.Key_Return || event.key === Qt.Key_Enter;
            if (event.key === Qt.Key_Escape)
                Capture.close();
            else if (Capture.textMode && Capture.zone) {
                if (ctrl && event.key === Qt.Key_A)
                    Capture.request("all");
                else if ((ctrl && event.key === Qt.Key_C) || enter)
                    Capture.copySelection();
                else if (event.key === Qt.Key_T)
                    Capture.textMode = false;
            } else if (Capture.textMode && event.key === Qt.Key_T)
                Capture.textMode = false;
            else if (enter)
                Capture.request("target");
            else if (event.key === Qt.Key_F)
                Capture.request("screen");
            else if (!Capture.textOnly && event.key === Qt.Key_T)
                Capture.textMode = true;
            event.accepted = true;
        }

        Image {
            id: frozen
            anchors.fill: parent
            source: root.monitor ? "file://" + Capture.image(root.name) : ""
        }

        // Dims everything but the target.
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.4
        }

        Item {
            id: spotlight

            visible: root.showZone || root.hovered || root.dragging
            x: root.spot.x
            y: root.spot.y
            width: root.spot.width
            height: root.spot.height
            clip: true

            Image {
                x: -spotlight.x
                y: -spotlight.y
                width: canvas.width
                height: canvas.height
                source: frozen.source
            }
        }

        Rectangle {
            visible: spotlight.visible
            x: spotlight.x
            y: spotlight.y
            width: spotlight.width
            height: spotlight.height
            color: "transparent"
            radius: root.showZone ? 0 : root.targetRadius
            border.color: Theme.accent
            border.width: 2
        }

        // Size of the dragged area, in pixels of the final image.
        Rectangle {
            visible: root.dragging && !root.selecting
            x: Math.min(spotlight.x + spotlight.width - width, canvas.width - width - Theme.gap)
            y: Math.min(spotlight.y + spotlight.height + Theme.gap, canvas.height - height - Theme.gap)
            width: size.implicitWidth + 2 * Theme.spacing
            height: size.implicitHeight + Theme.spacing
            radius: Theme.radius
            color: Theme.surface

            Text {
                id: size
                anchors.centerIn: parent
                text: Math.round(spotlight.width * root.ratio) + " × " + Math.round(spotlight.height * root.ratio)
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.smallSize
            }
        }

        Repeater {
            model: root.words

            Rectangle {
                required property var modelData
                required property int index

                readonly property bool selected: root.hasSelection && index >= root.selectionStart && index <= root.selectionEnd

                x: modelData.x - 2
                y: modelData.y - 2
                width: modelData.w + 4
                height: modelData.h + 4
                radius: 3
                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, selected ? 0.45 : 0.12)
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: root.zoneHere && root.contains(root.zoneRect, root.pointer) ? Qt.IBeamCursor : Qt.CrossCursor

            onEntered: Capture.hovered = root.name

            onPositionChanged: mouse => {
                Capture.hovered = root.name;
                root.pointer = Qt.point(mouse.x, mouse.y);
                if (!(pressedButtons & Qt.LeftButton))
                    return;
                if (!root.dragging && Math.hypot(mouse.x - root.pressPoint.x, mouse.y - root.pressPoint.y) > 4)
                    root.dragging = true;
                if (root.dragging && root.selecting)
                    root.select(root.anchorIndex, root.nearestWord(root.pointer));
            }

            onPressed: mouse => {
                if (mouse.button === Qt.RightButton) {
                    Capture.close();
                    return;
                }
                root.pointer = root.pressPoint = Qt.point(mouse.x, mouse.y);
                root.dragging = false;
                root.selecting = root.zoneHere && root.contains(root.zoneRect, root.pressPoint);
                if (root.selecting)
                    root.anchorIndex = root.nearestWord(root.pressPoint);
            }

            onReleased: mouse => {
                if (mouse.button !== Qt.LeftButton)
                    return;
                if (!root.selecting)
                    root.grab(root.target, root.targetRadius);
                else if (!root.dragging && !root.keepSelection)
                    Capture.select("", "");
                root.dragging = false;
                root.selecting = false;
                root.keepSelection = false;
            }

            onDoubleClicked: mouse => {
                const i = root.wordAt(Qt.point(mouse.x, mouse.y));
                if (!root.zoneHere || i < 0)
                    return;
                root.select(i, i);
                root.keepSelection = true;
            }
        }

        Rectangle {
            visible: root.hovered && !root.dragging
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6 * Theme.padding
            width: hintText.implicitWidth + 2 * Theme.padding
            height: hintText.implicitHeight + Theme.padding
            radius: Theme.radius
            color: Theme.surface
            border.color: Theme.highlightMed

            Text {
                id: hintText
                anchors.centerIn: parent
                text: root.hint
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
            }
        }
    }
}
