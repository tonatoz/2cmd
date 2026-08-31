import AppKit

let delegate = AppDelegate()
let application = NSApplication.shared
application.delegate = delegate
// Menu bar only: no Dock icon, no main window (also set via LSUIElement).
application.setActivationPolicy(.accessory)
application.run()
