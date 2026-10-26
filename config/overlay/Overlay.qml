import qs.services
import Quickshell

// One frozen overlay per monitor, created fresh each time it opens.
Scope {
    Variants {
        model: Capture.active ? Quickshell.screens : []

        ScreenOverlay {}
    }
}
