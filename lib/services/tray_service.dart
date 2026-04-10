import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:system_tray/system_tray.dart';

class TrayService {
  final SystemTray _tray = SystemTray();
  Menu _menu = Menu();
  bool _initialized = false;

  Future<void> init({
    required String title,
    required List<String> clipboardItems,
    required List<String> transferItems,
    required bool paused,
    required bool discoveryEnabled,
    required bool connected,
    required void Function() onShow,
    required void Function() onTogglePause,
    required void Function() onToggleDiscovery,
    required void Function() onDisconnect,
    required void Function() onQuit,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    if (_initialized) {
      await updateMenu(
        clipboardItems: clipboardItems,
        transferItems: transferItems,
        paused: paused,
        discoveryEnabled: discoveryEnabled,
        connected: connected,
        onShow: onShow,
        onTogglePause: onTogglePause,
        onToggleDiscovery: onToggleDiscovery,
        onDisconnect: onDisconnect,
        onQuit: onQuit,
      );
      return;
    }
    final iconPath = await _ensureIconPath();
    await _tray.initSystemTray(title: title, iconPath: iconPath);
    _tray.registerSystemTrayEventHandler((eventName) async {
      await _tray.popUpContextMenu();
    });
    await updateMenu(
      clipboardItems: clipboardItems,
      transferItems: transferItems,
      paused: paused,
      discoveryEnabled: discoveryEnabled,
      connected: connected,
      onShow: onShow,
      onTogglePause: onTogglePause,
      onToggleDiscovery: onToggleDiscovery,
      onDisconnect: onDisconnect,
      onQuit: onQuit,
    );
    _initialized = true;
  }

  Future<void> updateMenu({
    required List<String> clipboardItems,
    required List<String> transferItems,
    required bool paused,
    required bool discoveryEnabled,
    required bool connected,
    required void Function() onShow,
    required void Function() onTogglePause,
    required void Function() onToggleDiscovery,
    required void Function() onDisconnect,
    required void Function() onQuit,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) {
      return;
    }
    _menu = Menu();
    await _menu.buildFrom([
      MenuItemLabel(label: 'Show Wire', onClicked: (_) => onShow()),
      MenuItemLabel(label: paused ? 'Resume Sync' : 'Pause Sync', onClicked: (_) => onTogglePause()),
      MenuItemLabel(
        label: discoveryEnabled ? 'Stop Discovery' : 'Start Discovery',
        onClicked: (_) => onToggleDiscovery(),
      ),
      MenuItemLabel(label: 'Disconnect', onClicked: (_) => onDisconnect()),
      MenuItemLabel(label: connected ? 'Status: Connected' : 'Status: Disconnected', enabled: false),
      MenuSeparator(),
      MenuItemLabel(label: 'Clipboard History', enabled: false),
      ...clipboardItems.take(5).map((item) => MenuItemLabel(label: _truncate(item))),
      MenuSeparator(),
      MenuItemLabel(label: 'Transfers', enabled: false),
      ...transferItems.take(5).map((item) => MenuItemLabel(label: _truncate(item))),
      MenuSeparator(),
      MenuItemLabel(label: 'Quit', onClicked: (_) => onQuit()),
    ]);
    await _tray.setContextMenu(_menu);
  }

  String _truncate(String input) {
    if (input.length <= 40) return input;
    return '${input.substring(0, 37)}...';
  }

  Future<String> _ensureIconPath() async {
    final dir = await getTemporaryDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(p.join(dir.path, 'wire_tray.png'));
    if (!await file.exists()) {
      final bytes = base64Decode(_trayIconBase64);
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.path;
  }
}

const String _trayIconBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR4nGNgYAAAAAMAASsJTYQAAAAASUVORK5CYII=';
