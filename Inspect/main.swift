//
//  main.swift
//  Inspect
//
//  Explicit AppKit entry point. Using `@main` on an
//  NSApplicationDelegate-conforming NSObject does NOT auto-wire
//  the delegate to NSApplication.shared in the macOS 13 / Swift
//  5.10 SDK we target — NSApplication starts via the synthesized
//  `main()` but no AppDelegate instance is ever created, so
//  `applicationDidFinishLaunching` never fires. That meant the
//  status-bar icon never appeared and ⌃⌥⌘L was never registered.
//
//  Driving things from a plain main.swift removes the ambiguity:
//  we instantiate AppDelegate ourselves, assign it as the
//  delegate, and call run(). NSApplicationMain isn't needed once
//  this file exists.
//

import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
