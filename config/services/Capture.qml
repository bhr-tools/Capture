pragma Singleton
pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Io
import QtQuick

// State of the overlay and what it produces. A frame is a folder written by the
// wrapper at the keypress: one PNG per monitor and layout.json (hyprctl
// monitors and clients at that instant). Every capture is cropped from these
// files, so the result is exactly what the overlay shows.
Singleton {
    id: root

    property bool active: false
    // Opened with `capture text`: the selection is read as text, not saved.
    property bool textOnly: false
    // Live Text: an area is read, then its words can be selected and copied.
    property bool textMode: false
    property string frame: ""
    property var monitors: []
    property var clients: []
    // Cursor position at the keypress, in layout coordinates.
    property var cursor: ({ x: -1, y: -1 })
    // Hyprland's decoration:rounding, applied to captured windows.
    property int rounding: 0
    // Monitor under the pointer: keyboard actions apply to it.
    property string hovered: ""
    // Live Text area, { monitor, x, y, w, h } in image pixels, and its words
    // in image pixels too (null while the OCR runs).
    property var zone: null
    property var zoneWords: null
    // Bumped for each area, so a late OCR of a previous one is ignored.
    property int zoneSerial: 0
    // Text selected in Live Text mode, and the monitor it comes from.
    property string selection: ""
    property string selectionMonitor: ""

    readonly property string langs: Quickshell.env("CAPTURE_OCR_LANGS") || "eng"
    readonly property string screenshotDir: Quickshell.env("CAPTURE_SCREENSHOT_DIR") || Quickshell.env("HOME") + "/Pictures/Screenshots"

    // Asks the overlay of a monitor to act: "target" (what is under the
    // pointer), "screen" (the whole monitor) or "all" (select every word).
    // In Live Text mode, "target" and "screen" pick the area to read.
    signal requested(string monitor, string action)

    function image(monitor: string): string {
        return frame + "/" + monitor + ".png";
    }

    // The overlay shows up once layout.json is loaded: FileView reads
    // asynchronously, text() right after a path change still holds the
    // previous frame.
    function open(dir: string, textOnly: bool): void {
        root.textOnly = textOnly;
        layoutFile.path = dir + "/layout.json";
    }

    function show(dir: string, layout: var): void {
        frame = dir;
        monitors = layout.monitors;
        clients = layout.clients.filter(c => c.mapped && !c.hidden);
        cursor = layout.cursor;
        rounding = layout.rounding;
        hovered = (monitors.find(m => contains(m, cursor)) ?? monitors.find(m => m.focused) ?? monitors[0])?.name ?? "";
        textMode = false;
        active = true;
    }

    // Whether a monitor (hyprctl JSON) holds a point in layout coordinates.
    function contains(m: var, p: var): bool {
        const rotated = m.transform % 2 === 1;
        const width = (rotated ? m.height : m.width) / m.scale;
        const height = (rotated ? m.width : m.height) / m.scale;
        return p.x >= m.x && p.x < m.x + width && p.y >= m.y && p.y < m.y + height;
    }

    function close(): void {
        active = false;
        textMode = false;
    }

    function request(action: string): void {
        requested(hovered, action);
    }

    function select(monitor: string, text: string): void {
        selectionMonitor = monitor;
        selection = text;
    }

    // Crops a rectangle of a monitor, in image pixels: saved and copied as a
    // PNG, or read as text when opened with `capture text`. A radius makes the
    // corners transparent, so a window keeps its shape without its border.
    function capture(monitor: string, r: var): void {
        const geometry = `${r.w}x${r.h}+${r.x}+${r.y}`;
        if (textOnly)
            Quickshell.execDetached(["sh", "-c", readScript, "sh", image(monitor), geometry, langs]);
        else
            Quickshell.execDetached(["sh", "-c", saveScript, "sh", image(monitor), geometry, screenshotDir,
                                     `roundrectangle 0,0 ${r.w - 1},${r.h - 1} ${r.radius},${r.radius}`, String(r.radius)]);
        close();
    }

    // Without a selection, the whole area is copied.
    function copySelection(): void {
        const text = selection || join(zoneWords ?? [], 0, (zoneWords?.length ?? 0) - 1);
        if (text === "")
            return;
        Quickshell.execDetached(["wl-copy", "--", text]);
        close();
    }

    // Words from..to joined back: space, new line or blank line between
    // paragraphs.
    function join(words: var, from: int, to: int): string {
        let text = "";
        for (let i = from; i <= to; i++) {
            if (i > from)
                text += words[i].line === words[i - 1].line ? " " : words[i].par === words[i - 1].par ? "\n" : "\n\n";
            text += words[i].text;
        }
        return text;
    }

    onTextModeChanged: {
        select("", "");
        zoneSerial++;
        zone = null;
        zoneWords = null;
    }


    // --- Scripts: $1 image, $2 crop geometry, $3 OCR languages or output folder ---

    // $4 draws the mask of the rounded corners, used when the radius $5 is not 0.
    readonly property string saveScript: 'out="$3/$(date +%Y-%m-%d_%H-%M-%S).png"; mkdir -p "$3" || exit; if [ "$5" -gt 0 ]; then magick "$1" -crop "$2" +repage \\( +clone -alpha off -fill black -colorize 100 -fill white -draw "$4" \\) -alpha off -compose CopyOpacity -composite "$out"; else magick "$1" -crop "$2" +repage "$out"; fi && wl-copy --type image/png < "$out"'

    // A QR code wins over OCR: its content is what one wants to copy.
    readonly property string readScript: 'img=$(mktemp --suffix=.png); trap \'rm -f "$img"\' EXIT; magick "$1" -crop "$2" +repage -resize 200% "$img" || exit; text=$(zbarimg -q --raw "$img" 2>/dev/null) || text=$(tesseract "$img" stdout -l "$3" 2>/dev/null | tr -d "\\f"); [ -n "$text" ] && printf %s "$text" | wl-copy'

    // $4 is the upscale: small text reads much better on low density monitors.
    readonly property string ocrScript: 'magick "$1" -crop "$2" +repage -resize "$4%" png:- | tesseract stdin stdout -l "$3" tsv 2>/dev/null'


    // --- Live Text ---

    // Reads only this area, so a selection can never run outside of it.
    function readZone(monitor: string, r: var): void {
        select("", "");
        const serial = ++zoneSerial;
        zone = { monitor: monitor, x: r.x, y: r.y, w: r.w, h: r.h };
        zoneWords = null;
        const upscale = (monitors.find(m => m.name === monitor)?.scale ?? 1) < 1.5 ? 2 : 1;
        const proc = runner.createObject(root, {
            command: ["sh", "-c", ocrScript, "sh", image(monitor), `${r.w}x${r.h}+${r.x}+${r.y}`, langs, String(upscale * 100)],
            done: tsv => {
                if (root.zoneSerial === serial)
                    root.zoneWords = parse(tsv, upscale, r.x, r.y);
            }
        });
        proc.running = true;
    }

    // Keeps the words (level 5) of Tesseract's TSV, in reading order, moved
    // back to image pixels. `line` and `par` tell how to join them.
    function parse(tsv: string, upscale: int, dx: int, dy: int): var {
        const words = [];
        for (const row of tsv.split("\n")) {
            const f = row.split("\t");
            if (f.length < 12 || f[0] !== "5" || Number(f[10]) < 20 || f[11].trim() === "")
                continue;
            words.push({
                par: f[2] + "." + f[3],
                line: f[2] + "." + f[3] + "." + f[4],
                x: dx + f[6] / upscale,
                y: dy + f[7] / upscale,
                w: f[8] / upscale,
                h: f[9] / upscale,
                text: f[11]
            });
        }
        return words;
    }


    FileView {
        id: layoutFile

        onLoaded: {
            const dir = path.slice(0, path.lastIndexOf("/"));
            try {
                root.show(dir, JSON.parse(text()));
            } catch (e) {
                console.warn("capture: cannot read frame", dir, e);
            }
        }
        onLoadFailed: console.warn("capture: cannot read frame", path)
    }

    Component {
        id: runner

        Process {
            id: proc

            property var done

            stdout: StdioCollector {
                onStreamFinished: {
                    proc.done(text);
                    proc.destroy();
                }
            }
        }
    }
}
