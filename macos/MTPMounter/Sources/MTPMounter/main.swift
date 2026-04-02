import Foundation
import Network

#if os(macOS)
import AppKit
#endif

class MTPWebDAVServer {
    private var port: UInt16 = 8765
    private var listener: NWListener?
    private var mountPoint: String?
    private var isRunning = false
    
    func start() {
        print("🚀 Starting MTP WebDAV Server on port \(port)...")
        
        // Check if device is connected via MTP
        guard checkMTPDevice() else {
            print("❌ No MTP device detected. Please enable File Transfer mode on your Android device.")
            return
        }
        
        // Start WebDAV server
        startWebDAVServer()
        
        // Mount in Finder
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.mountInFinder()
        }
        
        // Keep running
        RunLoop.main.run()
    }
    
    private func checkMTPDevice() -> Bool {
        let task = Process()
        task.launchPath = "/opt/homebrew/bin/mtp-detect"
        task.arguments = []
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if output.contains("Found 1 device") || output.contains("Android device detected") {
                print("✅ MTP device detected!")
                return true
            }
        } catch {
            print("⚠️ Error running mtp-detect: \(error)")
        }
        
        return false
    }
    
    private func startWebDAVServer() {
        do {
            let parameters = NWParameters.tcp
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))
            
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            
            listener?.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("✅ WebDAV Server is ready on http://localhost:\(self.port)")
                    self.isRunning = true
                case .failed(let error):
                    print("❌ Server failed: \(error)")
                case .cancelled:
                    print("⚠️ Server cancelled")
                default:
                    break
                }
            }
            
            listener?.start(queue: .main)
        } catch {
            print("❌ Failed to start server: \(error)")
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                self?.handleRequest(data, connection: connection)
            }
            
            if isComplete {
                connection.cancel()
            } else if error == nil {
                // Continue receiving
                self?.handleConnection(connection)
            }
        }
    }
    
    private func handleRequest(_ data: Data, connection: NWConnection) {
        guard let request = String(data: data, encoding: .utf8) else { return }
        
        // Parse WebDAV request
        let lines = request.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return }
        
        let components = requestLine.components(separatedBy: " ")
        guard components.count >= 2 else { return }
        
        let method = components[0]
        let path = components[1]
        
        print("📥 \(method) \(path)")
        
        // Handle different WebDAV methods
        switch method {
        case "OPTIONS":
            sendOptionsResponse(connection)
        case "PROPFIND":
            sendPropfindResponse(path, connection)
        case "GET":
            sendGetResponse(path, connection)
        default:
            sendNotImplementedResponse(connection)
        }
    }
    
    private func sendOptionsResponse(_ connection: NWConnection) {
        let response = """
        HTTP/1.1 200 OK\r
        DAV: 1, 2\r
        Allow: OPTIONS, GET, HEAD, POST, DELETE, TRACE, PROPFIND, PROPPATCH, COPY, MOVE, LOCK, UNLOCK\r
        Content-Length: 0\r
        \r
        
        """
        
        sendResponse(response, connection)
    }
    
    private func sendPropfindResponse(_ path: String, _ connection: NWConnection) {
        // Get files from Android device via ADB
        let files = getFilesViaADB(path)
        
        let xmlBody = generatePropfindXML(path: path, files: files)
        
        let response = """
HTTP/1.1 207 Multi-Status\r
Content-Type: application/xml; charset=utf-8\r
Content-Length: \(xmlBody.utf8.count)\r
\r
\(xmlBody)
"""
        
        sendResponse(response, connection)
    }
    
    private func sendGetResponse(_ path: String, _ connection: NWConnection) {
        // Download file via ADB
        let androidPath = "/storage/emulated/0" + path
        let tempFile = NSTemporaryDirectory() + UUID().uuidString
        
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["adb", "pull", androidPath, tempFile]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if FileManager.default.fileExists(atPath: tempFile) {
                let data = try Data(contentsOf: URL(fileURLWithPath: tempFile))
                
                let response = """
HTTP/1.1 200 OK\r
Content-Type: application/octet-stream\r
Content-Length: \(data.count)\r
\r

"""
                
                sendResponse(response + String(data: data, encoding: .utf8)!, connection)
                
                try? FileManager.default.removeItem(atPath: tempFile)
            } else {
                sendNotFoundResponse(connection)
            }
        } catch {
            sendNotFoundResponse(connection)
        }
    }
    
    private func sendNotImplementedResponse(_ connection: NWConnection) {
        let response = """
HTTP/1.1 501 Not Implemented\r
Content-Length: 0\r
\r

"""
        sendResponse(response, connection)
    }
    
    private func sendNotFoundResponse(_ connection: NWConnection) {
        let response = """
HTTP/1.1 404 Not Found\r
Content-Length: 0\r
\r

"""
        sendResponse(response, connection)
    }
    
    private func sendResponse(_ response: String, _ connection: NWConnection) {
        let data = response.data(using: .utf8)!
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("❌ Send error: \(error)")
            }
        })
    }
    
    private func getFilesViaADB(_ path: String) -> [String] {
        let androidPath = "/storage/emulated/0" + path
        
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["adb", "shell", "ls", "-la", androidPath]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        var files: [String] = []
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            files = output.components(separatedBy: "\n")
                .filter { !$0.isEmpty && !$0.contains("total ") }
                .compactMap { line in
                    let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    return parts.count > 8 ? parts.last : nil
                }
        } catch {
            print("❌ ADB error: \(error)")
        }
        
        return files
    }
    
    private func generatePropfindXML(path: String, files: [String]) -> String {
        var xml = """
<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">

"""
        
        // Add current directory
        xml += """
<D:response>
    <D:href>\(path.isEmpty ? "/" : path)</D:href>
    <D:propstat>
        <D:prop>
            <D:resourcetype><D:collection/></D:resourcetype>
        </D:prop>
        <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
</D:response>

"""
        
        // Add files
        for file in files {
            let filePath = path + "/" + file
            xml += """
<D:response>
    <D:href>\(filePath)</D:href>
    <D:propstat>
        <D:prop>
            <D:resourcetype/>
            <D:getcontentlength>0</D:getcontentlength>
        </D:prop>
        <D:status>HTTP/1.1 200 OK</D:status>
    </D:propstat>
</D:response>

"""
        }
        
        xml += "</D:multistatus>"
        
        return xml
    }
    
    private func mountInFinder() {
        print("📱 Mounting Android device in Finder...")
        
        let mountPoint = "/Volumes/AndroidPhone"
        self.mountPoint = mountPoint
        
        // Create mount point
        try? FileManager.default.createDirectory(atPath: mountPoint, withIntermediateDirectories: true)
        
        // Mount using mount_webdav
        let task = Process()
        task.launchPath = "/sbin/mount_webdav"
        task.arguments = ["-i", "http://localhost:\(port)", mountPoint]
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                print("✅ Android phone mounted at \(mountPoint)")
                print("📂 Open Finder to access your files!")
                
                // Open Finder to the mount point
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: mountPoint)
            } else {
                print("❌ Failed to mount. Try manually: Go to Finder > Go > Connect to Server")
                print("   Enter: http://localhost:\(port)")
            }
        } catch {
            print("❌ Mount error: \(error)")
        }
    }
    
    deinit {
        listener?.cancel()
        if let mountPoint = mountPoint {
            let task = Process()
            task.launchPath = "/usr/sbin/diskutil"
            task.arguments = ["unmount", mountPoint]
            try? task.run()
        }
    }
}

// Main entry point
print("📱 Wire MTP Mounter for macOS")
print("================================")
print("")

let server = MTPWebDAVServer()
server.start()
