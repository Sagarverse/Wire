import FlutterMacOS
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif
import AVFoundation

class AudioState {
  var stream: Any? = nil
  var sink: FlutterEventSink? = nil
}

@main
class AppDelegate: FlutterAppDelegate {
  private let sharedFilesHandler = SharedFilesStreamHandler()
  private let clipboardHandler = ClipboardStreamHandler()
  private var channelsConfigured = false
  private let audioState = AudioState()

  // ── Status Bar ──────────────────────────────────────────────────────────────
  private var statusItem: NSStatusItem!
  private var mountMenuItem: NSMenuItem!
  private var connectionMenuItem: NSMenuItem!
  private var peerNameMenuItem: NSMenuItem!
  private var isMounted = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    setupStatusBar()
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      setupChannels(with: controller)
    }
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  func setupChannels(with controller: FlutterViewController) {
    if channelsConfigured {
      return
    }
    channelsConfigured = true
    let messenger = controller.engine.binaryMessenger
    let platformChannel = FlutterMethodChannel(name: "wire/platform", binaryMessenger: messenger)
    platformChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
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
        self.mainFlutterWindow?.makeKeyAndOrderFront(nil)
        result(true)
      case "revealInFinder":
        if let args = call.arguments as? [String: Any], let path = args["path"] as? String {
          let url = URL(fileURLWithPath: path)
          if FileManager.default.fileExists(atPath: path) {
              NSWorkspace.shared.activateFileViewerSelecting([url])
              result(true)
          } else {
              result(false)
          }
        } else {
          result(false)
        }
      case "hideApp":
        NSApp.hide(nil)
        result(true)
      case "openDownloadsFolder":
        var wireUrl: URL
        if let args = call.arguments as? [String: Any], let customPath = args["path"] as? String {
            wireUrl = URL(fileURLWithPath: customPath)
        } else {
            let downloadsUrl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            wireUrl = downloadsUrl.appendingPathComponent("Wire")
        }
        
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

      case "inputText":
        guard let args = call.arguments as? [String: Any],
              let text = args["text"] as? String else {
          result(false)
          return
        }
        let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
        guard trusted else {
          AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
          result(FlutterError(code: "ACCESSIBILITY_REQUIRED", message: "Needs Accessibility", details: nil))
          return
        }
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

      case "dispatchMouseEvent":
        guard let args = call.arguments as? [String: Any],
              let dx = args["dx"] as? Double,
              let dy = args["dy"] as? Double,
              let action = args["action"] as? String else {
          result(false)
          return
        }
        let trusted = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary)
        guard trusted else {
          result(FlutterError(code: "ACCESSIBILITY_REQUIRED", message: "Needs Accessibility", details: nil))
          return
        }
        var mouseLoc = NSEvent.mouseLocation
        guard let screen = NSScreen.main else { result(false); return }
        mouseLoc.y = screen.frame.height - mouseLoc.y
        let point = CGPoint(x: mouseLoc.x + CGFloat(dx), y: mouseLoc.y + CGFloat(dy))
        let src = CGEventSource(stateID: .hidSystemState)
        var eventType: CGEventType = .mouseMoved
        var mouseButton: CGMouseButton = .left
        switch action {
        case "move": eventType = .mouseMoved
        case "left_down": eventType = .leftMouseDown; mouseButton = .left
        case "left_up": eventType = .leftMouseUp; mouseButton = .left
        case "right_down": eventType = .rightMouseDown; mouseButton = .right
        case "right_up": eventType = .rightMouseUp; mouseButton = .right
        case "scroll":
            if let scrollEvent = CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) {
                scrollEvent.post(tap: .cghidEventTap)
            }
            result(true); return
        default: eventType = .mouseMoved
        }
        if let event = CGEvent(mouseEventSource: src, mouseType: eventType, mouseCursorPosition: point, mouseButton: mouseButton) {
            event.post(tap: .cghidEventTap)
        }
        result(true)

      case "ringPhone":
        self.playSystemSound()
        result(true)

      case "startAudioShare":
          self.startAudioCapture(result: result)
      case "stopAudioShare":
          self.stopAudioCapture(result: result)

      case "updateStatusBar":
        if let args = call.arguments as? [String: Any] {
          let connected = args["connected"] as? Bool ?? false
          let peerName = args["peerName"] as? String
          DispatchQueue.main.async {
            self.updateStatusBarState(connected: connected, peerName: peerName)
          }
        }
        result(true)

      case "updateMountStatus":
        if let args = call.arguments as? [String: Any] {
          let mounted = args["mounted"] as? Bool ?? false
          DispatchQueue.main.async {
            self.isMounted = mounted
            self.mountMenuItem?.title = mounted ? "⏏  Unmount Phone" : "📱  Mount Phone in Finder"
          }
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

    let audioChannel = FlutterEventChannel(name: "wire/audio_stream", binaryMessenger: messenger)
    audioChannel.setStreamHandler(AudioStreamHandler(callback: { [weak self] sink in
        self?.audioState.sink = sink
    }))
  }

  // --- ScreenCaptureKit Audio ---
  #if canImport(ScreenCaptureKit)
  @available(macOS 12.3, *)
  private func startAudioCapture(result: @escaping FlutterResult) {
      SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: true) { [weak self] (content: SCShareableContent?, error: Error?) in
          guard let self = self, let content = content, error == nil else {
              result(FlutterError(code: "SCK_ERROR", message: "Failed to get content", details: nil))
              return
          }
          let filter = SCContentFilter(display: content.displays[0], excludingWindows: [])
          let config = SCStreamConfiguration()
          config.capturesAudio = true
          // config.excludesCurrentProcessAudio = false // Requires macOS 14.0+
          self.audioState.stream = SCStream(filter: filter, configuration: config, delegate: nil)
          do {
              try (self.audioState.stream as? SCStream)?.addStreamOutput(self, type: .audio, sampleHandlerQueue: .global())
              (self.audioState.stream as? SCStream)?.startCapture { error in
                  if let error = error {
                      result(FlutterError(code: "SCK_START_FAILED", message: error.localizedDescription, details: nil))
                  } else { result(true) }
              }
          } catch {
              result(FlutterError(code: "SCK_INIT_FAILED", message: error.localizedDescription, details: nil))
          }
      }
  }

  @available(macOS 12.3, *)
  private func stopAudioCapture(result: @escaping FlutterResult) {
      (audioState.stream as? SCStream)?.stopCapture { _ in
          self.audioState.stream = nil
          result(true)
      }
  }
  #else
  private func startAudioCapture(result: @escaping FlutterResult) {
      result(FlutterError(code: "SDK_TOO_OLD", message: "Build SDK too old for SCKit", details: nil))
  }
  private func stopAudioCapture(result: @escaping FlutterResult) {
      result(true)
  }
  #endif

  private func playSystemSound() {
    let sound = NSSound(named: "Ping")
    sound?.play()
  }

  // ── Status Bar Setup ──────────────────────────────────────────────────────
  private func setupStatusBar() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    if let button = statusItem.button {
      button.image = NSImage(systemSymbolName: "bolt.horizontal.fill", accessibilityDescription: "Wire")
      button.image?.size = NSSize(width: 18, height: 18)
      button.image?.isTemplate = true
    }

    let menu = NSMenu()
    menu.autoenablesItems = false

    // ── Header ──
    let titleItem = NSMenuItem(title: "Wire", action: nil, keyEquivalent: "")
    titleItem.isEnabled = false
    let titleAttrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 13, weight: .heavy),
    ]
    titleItem.attributedTitle = NSAttributedString(string: "⚡ Wire", attributes: titleAttrs)
    menu.addItem(titleItem)

    // ── Connection Status ──
    connectionMenuItem = NSMenuItem(title: "⏳  Disconnected", action: nil, keyEquivalent: "")
    connectionMenuItem.isEnabled = false
    menu.addItem(connectionMenuItem)

    peerNameMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    peerNameMenuItem.isEnabled = false
    peerNameMenuItem.isHidden = true
    menu.addItem(peerNameMenuItem)

    menu.addItem(NSMenuItem.separator())

    // ── Show Wire ──
    let showItem = NSMenuItem(title: "🖥  Show Wire", action: #selector(showWireWindow), keyEquivalent: "w")
    showItem.keyEquivalentModifierMask = [.command, .shift]
    showItem.target = self
    menu.addItem(showItem)

    // ── Mount Toggle ──
    mountMenuItem = NSMenuItem(title: "📱  Mount Phone in Finder", action: #selector(toggleMount), keyEquivalent: "m")
    mountMenuItem.keyEquivalentModifierMask = [.command, .shift]
    mountMenuItem.target = self
    menu.addItem(mountMenuItem)

    // ── Open Downloads ──
    let dlItem = NSMenuItem(title: "📁  Open Downloads", action: #selector(openWireDownloads), keyEquivalent: "d")
    dlItem.keyEquivalentModifierMask = [.command, .shift]
    dlItem.target = self
    menu.addItem(dlItem)

    menu.addItem(NSMenuItem.separator())

    // ── Find Device ──
    let findItem = NSMenuItem(title: "🔔  Find Phone", action: #selector(findPhoneFromMenu), keyEquivalent: "f")
    findItem.keyEquivalentModifierMask = [.command, .shift]
    findItem.target = self
    menu.addItem(findItem)

    menu.addItem(NSMenuItem.separator())

    // ── Quit ──
    let quitItem = NSMenuItem(title: "Quit Wire", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    menu.addItem(quitItem)

    statusItem.menu = menu
  }

  private func updateStatusBarState(connected: Bool, peerName: String?) {
    if connected {
      connectionMenuItem?.title = "🟢  Connected"
      if let name = peerName, !name.isEmpty {
        peerNameMenuItem?.title = "      \(name)"
        peerNameMenuItem?.isHidden = false
      } else {
        peerNameMenuItem?.isHidden = true
      }
      // Update status bar icon tint via template
      if let button = statusItem?.button {
        button.image = NSImage(systemSymbolName: "bolt.horizontal.fill", accessibilityDescription: "Wire – Connected")
        button.image?.size = NSSize(width: 18, height: 18)
        button.image?.isTemplate = true
      }
    } else {
      connectionMenuItem?.title = "⏳  Disconnected"
      peerNameMenuItem?.isHidden = true
      if let button = statusItem?.button {
        button.image = NSImage(systemSymbolName: "bolt.horizontal", accessibilityDescription: "Wire – Disconnected")
        button.image?.size = NSSize(width: 18, height: 18)
        button.image?.isTemplate = true
      }
    }
  }

  @objc private func showWireWindow() {
    NSApp.activate(ignoringOtherApps: true)
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
  }

  @objc private func toggleMount() {
    if isMounted {
      unmountPhoneInFinder(result: { _ in })
      isMounted = false
      mountMenuItem?.title = "📱  Mount Phone in Finder"
    } else {
      mountPhoneInFinder(result: { [weak self] success in
        if let ok = success as? Bool, ok {
          DispatchQueue.main.async {
            self?.isMounted = true
            self?.mountMenuItem?.title = "⏏  Unmount Phone"
          }
        }
      })
    }
  }

  @objc private func openWireDownloads() {
    let downloadsUrl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    let wireUrl = downloadsUrl.appendingPathComponent("Wire")
    if !FileManager.default.fileExists(atPath: wireUrl.path) {
      try? FileManager.default.createDirectory(at: wireUrl, withIntermediateDirectories: true)
    }
    NSWorkspace.shared.open(wireUrl)
  }

  @objc private func findPhoneFromMenu() {
    // Send find_phone via the Flutter channel. We need to invoke Flutter.
    // For now, play a local sound and let the user use the main app for remote ring.
    if let controller = mainFlutterWindow?.contentViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "wire/statusbar", binaryMessenger: controller.engine.binaryMessenger)
      channel.invokeMethod("findPhone", arguments: nil)
    }
  }

  private func mountPhoneInFinder(result: @escaping FlutterResult) {
    guard let wrapperScriptPath = resolveWrapperScriptPath() else {
      result(FlutterError(code: "WRAPPER_SCRIPT_NOT_FOUND", message: "Mount wrapper script not found.", details: nil))
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let task = Process()
      task.executableURL = URL(fileURLWithPath: "/bin/bash")
      task.arguments = [wrapperScriptPath, "restart"]
      do {
        try task.run()
        task.waitUntilExit()
        DispatchQueue.main.async { result(task.terminationStatus == 0) }
      } catch {
        DispatchQueue.main.async { result(false) }
      }
    }
  }

  private func unmountPhoneInFinder(result: @escaping FlutterResult) {
    guard let wrapperScriptPath = resolveWrapperScriptPath() else { result(false); return }
    DispatchQueue.global(qos: .userInitiated).async {
      // Unmount the Finder volume
      let unmountTask = Process()
      unmountTask.executableURL = URL(fileURLWithPath: "/bin/bash")
      unmountTask.arguments = [wrapperScriptPath, "unmount"]
      try? unmountTask.run()
      unmountTask.waitUntilExit()

      // Also stop the background WebDAV server
      let stopTask = Process()
      stopTask.executableURL = URL(fileURLWithPath: "/bin/bash")
      stopTask.arguments = [wrapperScriptPath, "stop"]
      try? stopTask.run()
      stopTask.waitUntilExit()

      DispatchQueue.main.async { result(true) }
    }
  }


  private func resolveWrapperScriptPath() -> String? {
    let sourceFilePath = NSString(string: #filePath)
    let sourceRunnerDir = sourceFilePath.deletingLastPathComponent
    let sourceMacOSDir = NSString(string: sourceRunnerDir).deletingLastPathComponent
    let sourceProjectRoot = NSString(string: sourceMacOSDir).deletingLastPathComponent
    let path = NSString(string: sourceProjectRoot).appendingPathComponent("macos/mount-wire-phone.sh")
    return FileManager.default.fileExists(atPath: path) ? path : nil
  }
}

#if canImport(ScreenCaptureKit)
@available(macOS 12.3, *)
extension AppDelegate: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, let sink = audioState.sink else { return }
        if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            if let ptr = dataPointer {
                let data = Data(bytes: ptr, count: length)
                DispatchQueue.main.async { sink(data) }
            }
        }
    }
}
#endif

class AudioStreamHandler: NSObject, FlutterStreamHandler {
    private var callback: (FlutterEventSink?) -> Void
    init(callback: @escaping (FlutterEventSink?) -> Void) { self.callback = callback }
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        callback(events)
        return nil
    }
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        callback(nil)
        return nil
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
  func emit(paths: [String]) { eventSink?(paths) }
}

class ClipboardStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var timer: Timer?
  private var lastChangeCount: Int = NSPasteboard.general.changeCount
  private var lastEmittedText: String?
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events; lastChangeCount = NSPasteboard.general.changeCount; startTimer(); return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stopTimer(); eventSink = nil; return nil
  }
  private func startTimer() {
    timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in self?.pollPasteboard() }
  }
  private func stopTimer() { timer?.invalidate(); timer = nil }
  private func pollPasteboard() {
    let pasteboard = NSPasteboard.general
    let changeCount = pasteboard.changeCount
    if changeCount == lastChangeCount { return }
    lastChangeCount = changeCount
    guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return }
    if text == lastEmittedText { return }
    lastEmittedText = text; eventSink?(text)
  }
}
