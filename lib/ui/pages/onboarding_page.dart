import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:provider/provider.dart';
import '../../services/app_identity.dart';
import '../../services/permissions_service.dart';
import '../../services/discovery_service.dart';
import '../../providers/app_state.dart';
import '../widgets/glass_card.dart';
import '../../widgets/liquid_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../widgets/qr_pairing_dialog.dart';

class OnboardingPage extends StatefulWidget {
  final VoidCallback onFinish;

  const OnboardingPage({
    super.key,
    required this.onFinish,
  });

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();
  final TextEditingController _nameController = TextEditingController();
  final AppIdentity _identity = AppIdentity();
  final PermissionsService _permissions = PermissionsService();

  int _currentPage = 0;
  bool _isNotificationsGranted = false;
  bool _isBluetoothGranted = false;
  bool _isStorageGranted = false;
  bool _isSmsGranted = false;
  bool _isContactsGranted = false;

  final MobileScannerController _qrScanController = MobileScannerController();
  late AppState _appState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPermissions();
    });
  }

  Future<void> _checkPermissions() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final b = await _permissions.checkPermissionStatus(Permission.bluetoothScan);
    final n = await _permissions.checkPermissionStatus(Permission.notification);
    final s = await _permissions.checkPermissionStatus(Permission.storage);
    final sms = await _permissions.checkPermissionStatus(Permission.sms);
    final c = await _permissions.checkPermissionStatus(Permission.contacts);
    if (mounted) {
      setState(() {
        _isBluetoothGranted = b;
        _isNotificationsGranted = n;
        _isStorageGranted = s;
        _isSmsGranted = sms;
        _isContactsGranted = c;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appState = context.read<AppState>();
  }



  @override
  void dispose() {
    _qrScanController.dispose();
    _pageController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 5) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      await _identity.setDeviceName(name);
    }
    widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: LiquidBackground(
        child: Stack(
          children: [
            PageView(
              controller: _pageController,
              onPageChanged: (page) => setState(() => _currentPage = page),
              children: [
                _buildStep1(scheme),
                _buildStep2(scheme),
                _buildStep3(scheme),
                _buildStep4(scheme),
                _buildDiscoveryStep(scheme),
                _buildStep5(scheme),
              ],
            ),

            // Navigation overlays
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Indicators
                  Row(
                    children: List.generate(6, (index) => _buildIndicator(index, scheme)),
                  ),

                  // Next Button
                  ElevatedButton(
                    onPressed: _nextPage,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 8,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_currentPage == 5 ? 'GET STARTED' : 'CONTINUE',
                          style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Skip button
            if (_currentPage < 5)
              Positioned(
                top: 50,
                right: 20,
                child: TextButton(
                  onPressed: _finish,
                  child: Text('Skip Intro', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5))),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicator(int index, ColorScheme scheme) {
    bool isSelected = _currentPage == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(right: 6),
      height: 8,
      width: isSelected ? 24 : 8,
      decoration: BoxDecoration(
        color: isSelected ? scheme.primary : scheme.onSurface.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildStep1(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(30),
            ),
            child: Icon(Icons.bolt_rounded, size: 80, color: scheme.primary),
          ),
          const SizedBox(height: 40),
          Text(
            'Welcome to Wire',
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.bold,
              color: scheme.onSurface,
              letterSpacing: -1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Your devices, unified. Local-first, instant sync, zero cloud.',
            style: TextStyle(
              fontSize: 16,
              color: scheme.onSurface.withValues(alpha: 0.6),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStep2(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unfair Advantages',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: scheme.onSurface),
          ),
          const SizedBox(height: 30),
          _buildFeatureRow(Icons.content_copy_rounded, 'Universal Clipboard', 'Sync text instantly across devices.', scheme),
          _buildFeatureRow(Icons.dock_rounded, 'Liquid Glass Dock', 'Premium, haptic-enabled floating navigation.', scheme),
          _buildFeatureRow(Icons.folder_shared_rounded, 'File Sharing', 'Send files between devices instantly.', scheme),
          _buildFeatureRow(Icons.folder_shared_rounded, 'Remote Files', 'Browse and download from any linked device.', scheme),
          _buildFeatureRow(Icons.ring_volume_rounded, 'Find My Device', 'Ring at max volume to locate a lost device.', scheme),
        ],
      ),
    );
  }

  Widget _buildFeatureRow(IconData icon, String title, String desc, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: scheme.primary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 4),
                Text(desc, style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep3(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('IDENTIFY YOUR DEVICE', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold, fontSize: 11)),
          const SizedBox(height: 24),
          Text(
            'What should others call you?',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: scheme.onSurface),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.12), width: 1.5),
            ),
            child: TextField(
              controller: _nameController,
              decoration: InputDecoration(
                hintText: (kIsWeb ? false : defaultTargetPlatform == TargetPlatform.macOS) ? 'e.g. My MacBook' : 'e.g. Pixel 8',
                border: InputBorder.none,
                icon: Icon(Icons.alternate_email_rounded, color: scheme.primary, size: 20),
              ),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Visible to peers during discovery.',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.4), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildStep4(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Permissions',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: scheme.onSurface),
          ),
          const SizedBox(height: 12),
          Text('Wire needs access to work seamlessly.',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)),
            textAlign: TextAlign.center),
          const SizedBox(height: 40),
          _buildPermissionToggle('Connectivity', 'Nearby device discovery', _isBluetoothGranted, () async {
             final g = await _permissions.requestBluetooth();
             setState(() => _isBluetoothGranted = g);
          }, scheme),
          _buildPermissionToggle('Alerts', 'Real-time clipboard & sync', _isNotificationsGranted, () async {
             final g = await _permissions.requestNotifications();
             setState(() => _isNotificationsGranted = g);
          }, scheme),
          _buildPermissionToggle('Storage', 'File sharing & management', _isStorageGranted, () async {
             final g = await _permissions.requestStorage();
             setState(() => _isStorageGranted = g);
          }, scheme),
          _buildPermissionToggle('Messaging', 'Sync SMS & contacts', _isSmsGranted, () async {
             final g = await _permissions.requestSms();
             setState(() => _isSmsGranted = g);
          }, scheme),
          _buildPermissionToggle('Contacts', 'Resolve contact names', _isContactsGranted, () async {
             final g = await _permissions.requestContacts();
             setState(() => _isContactsGranted = g);
          }, scheme),
        ],
      ),
    );
  }

  Widget _buildPermissionToggle(String title, String desc, bool isGranted, VoidCallback onGrant, ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: GlassCard(
        accent: isGranted ? scheme.tertiary : scheme.outline,
        borderRadius: BorderRadius.circular(16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                   Text(desc, style: TextStyle(fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.5))),
                ],
              ),
            ),
            if (isGranted)
              const Icon(Icons.check_circle_rounded, color: Colors.green)
            else
              TextButton(
                onPressed: onGrant,
                child: const Text('GRANT'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveryStep(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('PAIR YOUR DEVICE', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold, fontSize: 11)),
          const SizedBox(height: 24),
          const Text(
            'Link by QR Code',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Show your QR code or scan the other device\'s code to pair instantly.',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          // Show My QR Code
          GlassCardInteractive(
            onTap: () => showDialog(
              context: context,
              builder: (_) => QrPairingDialog(
                deviceId: _appState.deviceId,
                deviceName: _appState.deviceName,
                port: 5757,
              ),
            ),
            padding: const EdgeInsets.all(20),
            borderRadius: BorderRadius.circular(20),
            accent: scheme.primary,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.qr_code_2_rounded, color: scheme.primary, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Show My QR Code',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text('Let the other device scan this',
                          style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withValues(alpha: 0.5))),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: scheme.onSurface.withValues(alpha: 0.3)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Scan QR Code
          GlassCardInteractive(
            onTap: _openQrScanner,
            padding: const EdgeInsets.all(20),
            borderRadius: BorderRadius.circular(20),
            accent: scheme.secondary,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.qr_code_scanner_rounded, color: scheme.secondary, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Scan QR Code',
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(height: 2),
                      Text("Point at the other device's QR code",
                          style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withValues(alpha: 0.5))),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    color: scheme.onSurface.withValues(alpha: 0.3)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextButton(
            onPressed: _nextPage,
            child: Text(
              'Skip for now',
              style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.4), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildStep5(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.celebration_rounded, size: 80, color: Colors.orange),
          const SizedBox(height: 30),
          const Text(
            'You\'re all wired up!',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Install Wire on your other devices to start the ultimate continuity experience.',
            style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  void _openQrScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Scan Pairing Code')),
          body: MobileScanner(
            controller: _qrScanController,
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                if (barcode.rawValue != null) {
                  try {
                    final data = jsonDecode(barcode.rawValue!);
                    final peer = DiscoveryPeerInfo(
                      address: data['ip'],
                      deviceId: data['id'],
                      deviceName: data['name'],
                      wsPort: data['port'],
                      filePort: data['filePort'] ?? 5758,
                    );
                    _appState.connectToPeer(
                      peer.address,
                      targetId: peer.deviceId,
                    );
                    Navigator.pop(context);
                    _nextPage();
                    return;
                  } catch (_) {}
                }
              }
            },
          ),
        ),
      ),
    );
  }
}
