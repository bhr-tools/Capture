import qs.services
import Quickshell
import Quickshell.Io

// Commands called by the `capture` wrapper, once it has frozen the screens.
Scope {
    IpcHandler {
        target: "capture"

        // Opens the overlay on a frame written by the wrapper.
        function open(frame: string): void { Capture.open(frame, false); }
        // Same overlay, but the selection is read and copied as text.
        function text(frame: string): void { Capture.open(frame, true); }
        function close(): void { Capture.close(); }
    }

    IpcHandler {
        target: "record"

        function toggle(monitor: string, audio: bool): void { Recorder.toggle(monitor, audio); }
        function stop(): void { Recorder.stop(); }
        function active(): bool { return Recorder.active; }
    }
}
