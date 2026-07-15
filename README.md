# Wire 🔌

**Wire** is a premium, high-performance, cross-platform mobile-to-desktop synchronization application built with Flutter. It seamlessly connects your Mac and Android devices, offering a professional, beautifully designed experience.

## ✨ Highlights

- **Professional UI/UX**: Completely redesigned with a stunning, vibrant teal-cyan aesthetic, glassmorphism elements, and liquid background animations.
- **Lightning Fast Sync**: Real-time clipboard sharing, remote file management, and instant notifications.
- **No-Config Pairing**: Simple QR code pairing with automatic local network discovery and fallback routing.
- **Native Performance**: Highly optimized background services ensure minimal battery drain while keeping devices constantly in sync.

## 🚀 Getting Started

**Prerequisites**: Flutter 3.10+, Dart 3.10+, macOS/Android SDKs

**Quick Start**:
```bash
git clone https://github.com/sagarm/wire.git
cd wire
flutter pub get
flutter run -d macos  # Run on Mac
flutter run -d android # Run on Phone
```

## 🎛️ Core Features

### 🔄 Real-Time Sync
- **Clipboard Sync**: Instantly share text between devices. Swipe to delete, tap to copy.
- **Notification Relay**: Receive and reply to phone notifications directly on your Mac.
- **Auto Discovery**: Devices automatically find each other on the local network.

### 🎮 Remote Control & Utility
- **Find Device**: Ring your misplaced phone directly from your Mac.
- **Remote File Access**: Browse, download, and manage your phone's files wirelessly.

### 📊 File Management
- **High-Speed Transfer**: Send files in batches with live progress indicators.
- **Transfer History**: Clean, organized history with file type icons and image previews.
- **macOS Integration**: Drag and drop files seamlessly.

### 🎨 Premium Design
- **ShareIt + KDE Connect Hybrid**: A beautiful, intuitive dashboard combining the best of both worlds.
- **Dynamic Theming**: True dark mode with deep navy tones and glowing cyan accents.
- **Fluid Animations**: Staggered entrances, pulsing connection indicators, and glassmorphic nav bars.

## 🛠️ Technology Stack

- **Frontend**: Flutter, Provider, Flutter Animate
- **Networking**: WebSockets, WebRTC (Signaling), Local Network Service Discovery (mDNS)
- **Background**: Flutter Background Service, Platform Channels (Kotlin/Swift)
- **Local Data**: SharedPreferences, SQLite

## 📱 Background Service (Android)

Wire utilizes a highly optimized foreground service on Android to ensure your clipboard and notifications stay synced even when the app is closed.
- Features a persistent, actionable notification (Sync, Ring, Stop).
- Efficient polling mechanisms to bypass Android 10+ clipboard restrictions.

## 🤝 Contributing

Contributions are welcome! Please ensure you:
- Follow standard Dart formatting (`dart format`).
- Maintain the premium UI/UX guidelines (use `app_theme.dart` colors and `LiquidBackground`).
- Test thoroughly on both macOS and Android before submitting a PR.

## 📄 License

Personal use license. See LICENSE file.

---
**Wire** • Seamless Device Sync • Fast • Beautiful • Privacy-First
