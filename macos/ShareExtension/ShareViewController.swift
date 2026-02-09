import Cocoa
import Social

class ShareViewController: NSViewController {
  override func viewDidAppear() {
    super.viewDidAppear()
    handleShare()
  }

  private func handleShare() {
    guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
      finishRequest()
      return
    }

    var paths: [String] = []
    let group = DispatchGroup()

    for item in items {
      guard let attachments = item.attachments else { continue }
      for provider in attachments {
        if provider.hasItemConformingToTypeIdentifier("public.file-url") {
          group.enter()
          provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
            if let url = data as? URL {
              paths.append(url.path)
            } else if let nsurl = data as? NSURL, let url = nsurl as URL? {
              paths.append(url.path)
            }
            group.leave()
          }
        }
      }
    }

    group.notify(queue: .main) { [weak self] in
      guard !paths.isEmpty else {
        self?.finishRequest()
        return
      }
      let encoded = paths
        .map { $0.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0 }
        .joined(separator: ",")
      if let url = URL(string: "wire://share?paths=\(encoded)") {
        NSWorkspace.shared.open(url)
      }
      self?.finishRequest()
    }
  }

  private func finishRequest() {
    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }
}
