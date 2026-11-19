import AppKit

// Development: render the simulation to an image and leave without starting the app.
if Preview.runIfRequested() { exit(0) }

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
let delegate = AppDelegate()
application.delegate = delegate
application.run()
