# Wire 🔌

**Wire** is a high-performance, cross-platform mobile-to-desktop synchronization application built with Flutter.

## Getting Started

**Prerequisites**: Flutter 3.10+, Dart 3.10+, platform SDKs

**Quick Start**:
```bash
git clone https://github.com/sagarm/wire.git
cd wire
flutter pub get
flutter run -d macos  # or ios, android
```

## Features

### 🔄 Real-Time Sync
- Clipboard sync with preview and clear history
- Fast file transfer with speed/ETA metrics
- WebDAV mount (macOS Finder integration)
- Notification relay with replies

### 🎮 Remote Control
- Keyboard mirror (live text input)
- Screen mirroring (WebRTC)
- Trackpad control
- URL handoff
- SMS management

### 📊 File Management
- Complete transfer history
- Batch retry/remove with undo (5s)
- Remote file browser
- Download folder integration
- Live transfer metrics

### ⚡ Optimized Performance
- Connection health metrics
- Memory/storage efficient
- Code shrinking & tree-shaking
- Lazy service loading
- <2s startup time

### 🎨 Modern UI
- Glass morphism design
- Dark/light themes
- Searchable quick commands (Cmd+K)
- Smooth animations
- Material Design 3

## Technology

- **Frontend**: Flutter (Dart) + Material 3
- **Communication**: WebSocket (5757) + HTTP (5758)
- **Streaming**: WebRTC
- **Storage**: SQLite
- **Integration**: Native channels

## Performance

- **App Size**: 180 MB (macOS), 120 MB (Android)
- **Memory**: 150-500 MB typical
- **Startup**: <2 seconds
- **Transfer Speed**: Network-limited, efficient chunking

## Configuration

### Theming
Edit `lib/ui/theme/app_theme.dart`:
- Primary: `Color(0xFF245DFF)`
- Font: SF Pro Text
- Border radius: 18px

### Optimization
Edit `lib/config/optimization_config.dart`:
- Queue size, heartbeat intervals, update frequencies

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Connection fails | Check firewall (5757/5758), manual reconnect |
| Transfer fails | Verify storage, network, permissions |
| Mirror doesn't work | Enable Labs → Mirror Features |
| App slow | Close other apps, check network, restart |

## Roadmap

- [ ] Biometric pairing
- [ ] Encrypted transfers
- [ ] Photo auto-sync
- [ ] Local P2P mode
- [ ] Hardware acceleration

## Contributing

- Follow Dart conventions (dartfmt)
- Add tests for features
- Update docs
- Test on multiple platforms

## License

Personal use license. See LICENSE file.

---

**Wire** • Seamless Device Sync • Fast • Responsive • Privacy-First


