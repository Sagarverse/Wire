import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private let sharedFilesHandler = SharedFilesStreamHandler()
  private let clipboardHandler = ClipboardStreamHandler()
  private var channelsConfigured = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      setupChannels(with: controller)
    }
  }

  func setupChannels(with controller: FlutterViewController) {
    if channelsConfigured {
      return
    }
    channelsConfigured = true
    let messenger = controller.engine.binaryMessenger
    let platformChannel = FlutterMethodChannel(name: "wire/platform", binaryMessenger: messenger)
    platformChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "getClipboardText":
        let pasteboard = NSPasteboard.general
        let text = pasteboard.string(forType: .string)
        result(text)
      case "setClipboardText":
        if let args = call.arguments as? [String: Any], let text = args["text"] as? String {
          let pasteboard = NSPasteboard.general
          pasteboard.clearContents()
          pasteboard.setString(text, forType: .string)
        }
        result(true)
      case "getClipboardImage":
        let pasteboard = NSPasteboard.general
        if let image = NSImage(pasteboard: pasteboard),
           let tiff = image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiff),
           let pngData = bitmapRep.representation(using: .png, properties: [:]) {
          result(pngData.base64EncodedString())
        } else {
          result(nil)
        }
      case "setClipboardImage":
        if let args = call.arguments as? [String: Any],
           let b64 = args["base64"] as? String,
           let data = Data(base64Encoded: b64),
           let image = NSImage(data: data) {
          let pasteboard = NSPasteboard.general
          pasteboard.clearContents()
          pasteboard.writeObjects([image])
          result(true)
        } else {
          result(false)
        }
      case "activateApp":
        NSApp.activate(ignoringOtherApps: true)
        result(true)
      case "revealInFinder":
        if let args = call.arguments as? [String: Any], let path = args["path"] as? String {
          let url = URL(fileURLWithPath: path)
          NSWorkspace.shared.activateFileViewerSelecting([url])
          result(true)
        } else {
          result(false)
        }
      case "hideApp":
        NSApp.hide(nil)
        result(true)
      case "openDownloadsFolder":
        let downloadsUrl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let wireUrl = downloadsUrl.appendingPathComponent("Wire")
        if !FileManager.default.fileExists(atPath: wireUrl.path) {
            try? FileManager.default.createDirectory(at: wireUrl, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(wireUrl)
        result(true)
      case "mountPhoneInFinder":
        self.mountPhoneInFinder(result: result)
      case "unmountPhoneInFinder":
        self.unmountPhoneInFinder(result: result)
      case "setFocusMode":
        if let args = call.arguments as? [String: Any], let _ = args["enabled"] as? Bool {
          result(true)
        } else {
          result(false)
        }

      // --- Media Controls ---
      case "mediaPlayPause":
        // Media key simulation disabled due to HardwareKeyboard state conflicts
        // AppDelegate.simulateMediaKey(keyCode: NX_KEYTYPE_PLAY)
        result(true)
      case "mediaNext":
        // AppDelegate.simulateMediaKey(keyCode: NX_KEYTYPE_FAST)
        result(true)
      case "mediaPrevious":
        // AppDelegate.simulateMediaKey(keyCode: NX_KEYTYPE_REWIND)
        result(true)
      case "volumeUp":
        // AppDelegate.simulateMediaKey(keyCode: NX_KEYTYPE_SOUND_UP)
        result(true)
      case "volumeDown":
        // AppDelegate.simulateMediaKey(keyCode: NX_KEYTYPE_SOUND_DOWN)
        result(true)
      case "volumeMute":
        // AppDelegate.simulateMediaKey(keyCode: NX_KEYTYPE_MUTE)
        result(true)

      // --- Keyboard Mirroring via CGEvent ---
      case "inputText":
        guard let args = call.arguments as? [String: Any],
              let text = args["text"] as? String else {
          result(false)
          return
        }
        // Check Accessibility permission first
        let trusted = AXIsProcessTrustedWithOptions(
          [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        )
        guard trusted else {
          // Prompt for Accessibility permission
          AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
          )
          result(FlutterError(
            code: "ACCESSIBILITY_REQUIRED",
            message: "Wire needs Accessibility access to mirror keyboard. Please grant it in System Settings → Privacy & Security → Accessibility.",
            details: nil
          ))
          return
        }
        // Inject each unicode character as a key event pair
        let src = CGEventSource(stateID: .hidSystemState)
        for scalar in text.unicodeScalars {
          var uniChar = UniChar(scalar.value & 0xFFFF)
          if let keyDown = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
            keyDown.keyboardSetUnicodeString(stringLength: 1, unicodeString: &uniChar)
            keyDown.post(tap: .cghidEventTap)
          }
          if let keyUp = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
            keyUp.keyboardSetUnicodeString(stringLength: 1, unicodeString: &uniChar)
            keyUp.post(tap: .cghidEventTap)
          }
        }
        result(true)

      case "inputKeyEvent":
        guard let args = call.arguments as? [String: Any],
              let keyCode = args["keyCode"] as? Int,
              let action = args["action"] as? String else {
          result(false)
          return
        }

        let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
        guard trusted else {
          result(FlutterError(code: "ACCESSIBILITY_REQUIRED", message: "Needs Accessibility", details: nil))
          return
        }

        let src = CGEventSource(stateID: .hidSystemState)
        if action == "down" || action == "press" {
          let eventDown = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: true)
          eventDown?.post(tap: .cghidEventTap)
        }
        if action == "up" || action == "press" {
          let eventUp = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keyCode), keyDown: false)
          eventUp?.post(tap: .cghidEventTap)
        }
        result(true)

      case "getAccessibilityStatus":
        let trusted = AXIsProcessTrustedWithOptions(nil)
        result(trusted)

      case "requestAccessibility":
        AXIsProcessTrustedWithOptions(
          [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        )
        result(true)

      case "dispatchMouseEvent":
        guard let args = call.arguments as? [String: Any],
              let dx = args["dx"] as? Double,
              let dy = args["dy"] as? Double,
              let action = args["action"] as? String else {
          result(false)
          return
        }

        let trusted = AXIsProcessTrustedWithOptions(
          [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        )
        guard trusted else {
          result(FlutterError(
            code: "ACCESSIBILITY_REQUIRED",
            message: "Wire needs Accessibility access to control the mouse.",
            details: nil
          ))
          return
        }

        // Get current mouse location
        var mouseLoc = NSEvent.mouseLocation
        // NSEvent.mouseLocation has (0,0) at bottom-left. CGEvent wants (0,0) at top-left.
        // We need the screen height to flip the Y coordinate.
        guard let screen = NSScreen.main else {
            result(false)
            return
        }
        let screenHeight = screen.frame.height
        mouseLoc.y = screenHeight - mouseLoc.y

        let newX = mouseLoc.x + CGFloat(dx)
        let newY = mouseLoc.y + CGFloat(dy)
        let point = CGPoint(x: newX, y: newY)

        let src = CGEventSource(stateID: .hidSystemState)
        var eventType: CGEventType = .mouseMoved
        var mouseButton: CGMouseButton = .left

        switch action {
        case "move":
            eventType = .mouseMoved
        case "left_down":
            eventType = .leftMouseDown
            mouseButton = .left
        case "left_up":
            eventType = .leftMouseUp
            mouseButton = .left
        case "right_down":
            eventType = .rightMouseDown
            mouseButton = .right
        case "right_up":
            eventType = .rightMouseUp
            mouseButton = .right
        case "scroll":
            if let scrollEvent = CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) {
                scrollEvent.post(tap: .cghidEventTap)
            }
            result(true)
            return
        default:
            eventType = .mouseMoved
        }

        if let event = CGEvent(mouseEventSource: src, mouseType: eventType, mouseCursorPosition: point, mouseButton: mouseButton) {
            event.post(tap: .cghidEventTap)
        }
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let sharedChannel = FlutterEventChannel(name: "wire/shared_files", binaryMessenger: messenger)
    sharedChannel.setStreamHandler(sharedFilesHandler)

    let clipboardChannel = FlutterEventChannel(name: "wire/clipboard_events", binaryMessenger: messenger)
    clipboardChannel.setStreamHandler(clipboardHandler)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    sharedFilesHandler.emit(paths: filenames)
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      if url.scheme == "wire", url.host == "share" {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let pathsItem = components?.queryItems?.first(where: { $0.name == "paths" })?.value ?? ""
        let paths = pathsItem
          .split(separator: ",")
          .map { String($0).removingPercentEncoding ?? String($0) }
          .filter { !$0.isEmpty }
        if !paths.isEmpty {
          sharedFilesHandler.emit(paths: paths)
        }
      }
    }
  }

  static func simulateMediaKey(keyCode: Int32) {
      guard let src = CGEventSource(stateID: .hidSystemState) else { return }

      // Fallback that compiles across current macOS SDKs.
      // Some SDKs no longer expose .systemDefined/.customObjCType as used in older media-key injection code.
      let virtualKey = CGKeyCode(max(0, keyCode))
      let eventDown = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: true)
      eventDown?.post(tap: .cgSessionEventTap)

      let eventUp = CGEvent(keyboardEventSource: src, virtualKey: virtualKey, keyDown: false)
      eventUp?.post(tap: .cgSessionEventTap)
  }

  private func wrapperScriptCandidates() -> [String] {
    let fileManager = FileManager.default
    let currentDirectory = fileManager.currentDirectoryPath

    let sourceFilePath = NSString(string: #filePath)
    let sourceRunnerDir = sourceFilePath.deletingLastPathComponent
    let sourceMacOSDir = NSString(string: sourceRunnerDir).deletingLastPathComponent
    let sourceProjectRoot = NSString(string: sourceMacOSDir).deletingLastPathComponent

    let sourceCandidate = NSString(string: sourceProjectRoot)
      .appendingPathComponent("macos/mount-wire-phone.sh")

    let cwdCandidate = NSString(string: currentDirectory)
      .appendingPathComponent("macos/mount-wire-phone.sh")

    let homeCandidate = (NSHomeDirectory() as NSString)
      .appendingPathComponent("Workstation/wire/macos/mount-wire-phone.sh")

    let bundleCandidate = URL(fileURLWithPath: Bundle.main.bundlePath)
      .appendingPathComponent("../../../../../../macos/mount-wire-phone.sh")
      .standardizedFileURL.path

    var ordered: [String] = []
    for candidate in [sourceCandidate, cwdCandidate, homeCandidate, bundleCandidate] {
      if !ordered.contains(candidate) {
        ordered.append(candidate)
      }
    }
    return ordered
  }

  private func resolveWrapperScriptPath() -> String? {
    for candidate in wrapperScriptCandidates() {
      if FileManager.default.fileExists(atPath: candidate) {
        return candidate
      }
    }
    return nil
  }

  private func mountPhoneInFinder(result: @escaping FlutterResult) {
    guard let wrapperScriptPath = resolveWrapperScriptPath() else {
      let details = [
        "searched": wrapperScriptCandidates(),
        "cwd": FileManager.default.currentDirectoryPath,
        "bundlePath": Bundle.main.bundlePath,
      ] as [String : Any]
      result(FlutterError(code: "WRAPPER_SCRIPT_NOT_FOUND", message: "Mount wrapper script not found.", details: details))
      return
    }

    DispatchQueue.global(qos: .userInitiated).async {
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/bin/bash")
      task.arguments = [wrapperScriptPath, "restart"]

      let outputPipe = Pipe()
      task.standardOutput = outputPipe
      task.standardError = outputPipe

      do {
        try task.run()
        task.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        DispatchQueue.main.async {
          if task.terminationStatus == 0 {
            NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("WirePhone"))
            result(true)
          } else {
            result(FlutterError(code: "MOUNT_FAILED", message: "Failed to mount phone in Finder.", details: output))
          }
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "MOUNT_ERROR", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func unmountPhoneInFinder(result: @escaping FlutterResult) {
    guard let wrapperScriptPath = resolveWrapperScriptPath() else {
      result(false)
      return
    }

    DispatchQueue.global(qos: .userInitiated).async {
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/bin/bash")
      task.arguments = [wrapperScriptPath, "unmount"]
      do {
        try task.run()
        task.waitUntilExit()
        DispatchQueue.main.async {
          result(task.terminationStatus == 0)
        }
      } catch {
        DispatchQueue.main.async {
          result(false)
        }
      }
    }
  }
}

class SharedFilesStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func emit(paths: [String]) {
    eventSink?(paths)
  }
}

class ClipboardStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var timer: Timer?
  private var lastChangeCount: Int = NSPasteboard.general.changeCount
  private var lastEmittedText: String?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    lastChangeCount = NSPasteboard.general.changeCount
    startTimer()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stopTimer()
    eventSink = nil
    return nil
  }

  private func startTimer() {
    if timer != nil {
      return
    }
    timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
      self?.pollPasteboard()
    }
  }

  private func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  private func pollPasteboard() {
    let pasteboard = NSPasteboard.general
    let changeCount = pasteboard.changeCount
    if changeCount == lastChangeCount {
      return
    }
    lastChangeCount = changeCount
    guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
      return
    }
    if text == lastEmittedText {
      return
    }
    lastEmittedText = text
    eventSink?(text)
  }
}
