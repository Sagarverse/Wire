import 'package:flutter/foundation.dart';
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
    required Map<String, dynamic> state,
    required void Function(String method, dynamic args) onAction,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;

    if (!_initialized) {
      final iconPath = await _ensureIconPath();
      debugPrint('TrayService: Initializing with icon path: $iconPath');
      await _tray.initSystemTray(title: 'Wire Sync', iconPath: iconPath);
      _tray.registerSystemTrayEventHandler((eventName) async {
        debugPrint('TrayService: Event received: $eventName');
        if (eventName == 'leftMouseDown' || eventName == 'rightMouseDown' || eventName == 'leftMouseUp' || 
            eventName == 'click' || eventName == 'right-click') {
           await _tray.popUpContextMenu();
        }
      });
      _initialized = true;
    debugPrint('TrayService: Initialization complete.');
    }

    await updateMenu(state: state, onAction: onAction);
  }

  Future<void> updateMenu({
    required Map<String, dynamic> state,
    required void Function(String method, dynamic args) onAction,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;

    final String mode = state['mode'] ?? 'auto';
    final bool isPaused = state['paused'] ?? false;
    final bool discoveryEnabled = state['discovery'] ?? true;
    final bool clipboardEnabled = state['clipboardEnabled'] ?? true;
    final bool focusMode = state['focusMode'] ?? false;
    final bool isConnected = state['connected'] ?? false;
    final String? peerName = state['peerName'];
    final int? battery = state['battery'];
    final bool? isCharging = state['batteryCharging'];
    
    final List<dynamic> clipboard = state['clipboardHistory'] ?? [];
    final List<dynamic> transfers = state['recentTransfers'] ?? [];
    final List<dynamic> nearby = state['nearbyPeers'] ?? [];

    _menu = Menu();
    
    await _menu.buildFrom([
      MenuItemLabel(
        label: isConnected ? 'Connected: ${peerName ?? 'Device'}' : 'Status: Ready', 
        enabled: false,
      ),
      MenuItemLabel(label: 'Dashboard (Show UI)', onClicked: (_) => onAction('show_window', null)),
      if (isConnected && battery != null)
        MenuItemLabel(
          label: 'Battery: $battery%${isCharging == true ? ' (Charging)' : ''}', 
          enabled: false,
        ),
      MenuSeparator(),
      
      MenuItemLabel(label: 'Dashboard', onClicked: (_) => onAction('show_window', null)),
      MenuItemLabel(label: 'Manual Pairing...', onClicked: (_) => onAction('manual_pairing', null)),
      
      // Connection Mode Submenu
      SubMenu(
        label: 'Connection Mode: ${mode.toUpperCase()}',
        children: [
          MenuItemCheckbox(
            label: 'Auto (Smart)', 
            checked: mode == 'auto',
            onClicked: (_) => onAction('set_mode', 'auto'),
          ),
          MenuItemCheckbox(
            label: 'Local Wi-Fi Only', 
            checked: mode == 'local',
            onClicked: (_) => onAction('set_mode', 'local'),
          ),
          MenuItemCheckbox(
            label: 'Internet Only (P2P)', 
            checked: mode == 'p2p',
            onClicked: (_) => onAction('set_mode', 'p2p'),
          ),
        ],
      ),

      // Nearby Devices Submenu
      SubMenu(
        label: 'Nearby Devices (${nearby.length})',
        children: [
          if (nearby.isEmpty)
            MenuItemLabel(label: 'No devices found', enabled: false)
          else
            ...nearby.map((peer) => MenuItemLabel(
              label: '${peer['deviceName']} (${peer['mode']})',
              onClicked: (_) => onAction('pair_device', peer),
            )),
        ],
      ),

      MenuSeparator(),

      // Quick Settings Submenu
      SubMenu(
        label: 'Quick Settings',
        children: [
          MenuItemCheckbox(
            label: 'Active Discovery', 
            checked: discoveryEnabled,
            onClicked: (_) => onAction('toggle_discovery', !discoveryEnabled),
          ),
          MenuItemCheckbox(
            label: 'Clipboard Sync', 
            checked: clipboardEnabled,
            onClicked: (_) => onAction('toggle_clipboard', !clipboardEnabled),
          ),
          MenuItemCheckbox(
            label: 'Focus Mode', 
            checked: focusMode,
            onClicked: (_) => onAction('toggle_focus', !focusMode),
          ),
        ],
      ),

      MenuItemLabel(
        label: isPaused ? 'Resume Sync' : 'Pause Sync', 
        onClicked: (_) => onAction('toggle_pause', !isPaused),
      ),
      
      if (isConnected) 
        MenuItemLabel(label: 'Find My Phone', onClicked: (_) => onAction('find_phone', null)),

      MenuSeparator(),

      // Lists
      SubMenu(
        label: 'Recent Clipboard',
        children: [
          if (clipboard.isEmpty)
             MenuItemLabel(label: 'History empty', enabled: false)
          else ...[
            ...clipboard.take(5).map((item) => MenuItemLabel(
              label: _truncate(item.toString()),
              onClicked: (_) => onAction('copy_to_clipboard', item),
            )),
            MenuSeparator(),
            MenuItemLabel(label: 'Clear History', onClicked: (_) => onAction('clear_clipboard', null)),
          ],
        ],
      ),

      SubMenu(
        label: 'Recent Transfers',
        children: [
          MenuItemLabel(label: 'Open Downloads Folder', onClicked: (_) => onAction('open_downloads', null)),
          MenuSeparator(),
          if (transfers.isEmpty)
             MenuItemLabel(label: 'No recent transfers', enabled: false)
          else
            ...transfers.take(5).map((file) => MenuItemLabel(
              label: _truncate(file['name'] ?? 'File'),
              onClicked: (_) => onAction('open_file', file['path']),
            )),
        ],
      ),

      MenuSeparator(),
      MenuItemLabel(label: 'Quit Wire', onClicked: (_) => onAction('quit', null)),
    ]);

    debugPrint('TrayService: Menu build complete. Setting context menu...');
    await _tray.setContextMenu(_menu);
    debugPrint('TrayService: Context menu set successfully.');
  }

  String _truncate(String input) {
    if (input.length <= 35) return input;
    return '${input.substring(0, 32)}...';
  }

  Future<String> _ensureIconPath() async {
    final dir = await getTemporaryDirectory();
    final iconDir = Directory(p.join(dir.path, 'wire_sync'));
    if (!await iconDir.exists()) {
      await iconDir.create(recursive: true);
    }
    
    final file = File(p.join(iconDir.path, 'wire_trayTemplate.png'));
    if (!await file.exists() || (await file.length() == 0)) {
      final bytes = base64Decode(_trayIconBase64);
      await file.writeAsBytes(bytes, flush: true);
    }
    return file.path;
  }
}

const String _trayIconBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAACXBIWXMAAAsTAAALEwEAmpwYAAACv0lEQVRYhe2Xz2vTYBzG389be9u6ttY63Y6pM90Y6mZisD8oInY7DIIiInY7DIIiInY7DIIiInY7DIIiIuK/oAdPHjx48ODBgwfPnDztLre979uDpInSrtXW6pS88Asv8PDm9/l+8uT98BCYYYclA8A7LOnBf1h7f07Y4eZ2f3D94Rff7v7mH/X9fWGHpU1X0Lp6D61B7X4U7LD0uL/98OveT/+0H+xHPrG77Z/K4HhVvYvWqHbPFXZYfnm38+D8z59/60f70Y/stX9qZfBa9R5ao9o9L9jhvV+f798p/eInOnL82f6pjUFr1XtojWr3YmCH77eeFp/+OnYf6cjxl/unNoatVe+hNardG4Adfrp7svf9fvwT6cjxl/unNwS9qffQGtXuvU7Y4deHh96vXf1H6cjxlfun9zV6U++hNar90z8IdljZeNR7qSInD+V091HvtYZ89R5ao9o9i3zCDe4/OdxT0YsnOnL67uPekIa89B5ao9o9C79f4Aatp0cHvWUnP9GR819ev98S8tH7aI1q9yyyzSfcun3UvVGVC6c6cvnr6Z9tIT+9j9aodq8n2eITbt886PxWlUunevHndO9HByC9v0Zvd98N9lK7H7Wrv9940HtVlUune3H/7NHBnkh6f43e7r4X7KV2P6rnK9z2/f3e79WofvCjPHh7rPdTIUnnr9Fr990In6pX6vNf4Y7vH+5fqYruR3kw1evpU6Ik6bw1eq07f8An/YDP+gnX7p7urVTF8KM8mOn15At6knT+Gr0v+AE7fNJPfOIOv6rF4f7rR0Gis9eTk6pDkrT9Gv3En+CrvvAlO3zm7h3sX70Msh/lQT+X7X0iSdqv0U98whf6wi/Z4XOnP9h7vR66H+VBP5f9qC9JWq/RT3zC7/glP/GX7PDlwO/v9R8Hia7eF105qfqSrPUVfuET/sMv+aH9Sdrh657fP9h/fRAku3qfdOWv1Vfor4XF9M8XfP8AAtw8IqjAL0MAAAAASUVORK5CYII=';
