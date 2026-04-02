#!/bin/bash

echo "📱 Wire Phone Mounter - Connecting your Android to macOS Finder"
echo "================================================================"
echo ""

# Check if phone is connected
if ! adb devices | grep -q "device$"; then
    echo "❌ No Android device found. Please connect via USB and enable USB debugging."
    exit 1
fi

echo "✅ Android device detected!"
echo ""
echo "🚀 Starting ADB file server on http://localhost:8765..."
echo ""

# Start simple Python HTTP server using ADB
python3 -c "
import http.server
import socketserver
import subprocess
import urllib.parse
import os

PORT = 8765

class ADBFileHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        # Parse path
        path = urllib.parse.unquote(self.path)
        if path == '/':
            path = '/storage/emulated/0'
        else:
            path = '/storage/emulated/0' + path
        
        # Get file via ADB
        temp_file = '/tmp/adb_temp_file'
        result = subprocess.run(['adb', 'pull', path, temp_file], 
                                capture_output=True, text=True)
        
        if os.path.exists(temp_file):
            with open(temp_file, 'rb') as f:
                content = f.read()
            
            self.send_response(200)
            self.send_header('Content-Type', 'application/octet-stream')
            self.send_header('Content-Length', str(len(content)))
            self.end_headers()
            self.wfile.write(content)
            os.remove(temp_file)
        else:
            self.send_response(404)
            self.end_headers()

with socketserver.TCPServer(('', PORT), ADBFileHandler) as httpd:
    print(f'✅ Server running on http://localhost:{PORT}')
    print('')
    print('📂 To access files:')
    print('1. Open Finder')
    print('2. Press Cmd+K or Go > Connect to Server')
    print(f'3. Enter: http://localhost:{PORT}')
    print('4. Click Connect')
    print('')
    print('Press Ctrl+C to stop')
    httpd.serve_forever()
"
