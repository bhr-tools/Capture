pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Records a whole monitor with wf-recorder. While it runs, the path of the
// video is written to $XDG_RUNTIME_DIR/capture/recording (empty otherwise) so
// a bar can show it. Once stopped, the file is copied to the clipboard.
Singleton {
    id: root

    readonly property bool active: proc.running
    property string file: ""

    readonly property string dir: Quickshell.env("CAPTURE_SCREENCAST_DIR") || Quickshell.env("HOME") + "/Videos/Screencasts"

    function toggle(monitor: string, audio: bool): void {
        if (active)
            stop();
        else
            start(monitor, audio);
    }

    function start(monitor: string, audio: bool): void {
        if (active)
            return;
        file = dir + "/" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss") + ".mp4";
        proc.command = ["sh", "-c", 'mkdir -p "$(dirname "$1")" && exec wf-recorder -f "$@"', "sh", file, "-o", monitor, ...(audio ? ["--audio"] : [])];
        proc.running = true;
    }

    // SIGINT: wf-recorder finishes writing the file before exiting.
    function stop(): void {
        if (active)
            proc.signal(2);
    }

    onActiveChanged: status.setText(active ? file : "")
    Component.onCompleted: status.setText("")


    Process {
        id: proc

        onExited: code => {
            if (code === 0)
                Quickshell.execDetached(["wl-copy", "--type", "text/uri-list", "file://" + root.file]);
            else
                console.warn("capture: wf-recorder exited with", code);
        }
    }

    FileView {
        id: status
        printErrors: false
        path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/capture/recording"
    }
}
