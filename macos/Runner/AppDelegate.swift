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
