import 'dart:io';
import 'package:system_tray/system_tray.dart';

class TrayService {
  final SystemTray _systemTray = SystemTray();
  final Menu _menu = Menu();

  Future<void> init({
    required Map<String, dynamic> state,
    required void Function(String method, dynamic args) onAction,
  }) async {
    // Mac likes template images for the tray (wire_tray.png)
    String iconPath = Platform.isWindows ? 'assets/images/wire_icon.ico' : 'assets/images/wire_tray.png';

    await _systemTray.initSystemTray(
      title: "W",
      iconPath: iconPath,
    );

    // Register click event to show window
    _systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        onAction('show_window', null);
      } else if (eventName == kSystemTrayEventRightClick) {
        _systemTray.popUpContextMenu();
      }
    });

    await updateMenu(state: state, onAction: onAction);
  }

  Future<void> updateMenu({
    required Map<String, dynamic> state,
    required void Function(String method, dynamic args) onAction,
  }) async {
    final List<MenuItemBase> items = [
      MenuItemLabel(
        label: 'Show Wire',
        onClicked: (menuItem) => onAction('show_window', null),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Status: ${state['connected'] == true ? "Connected to ${state['peerName']}" : "Disconnected"}',
        enabled: false,
      ),
    ];

    if (state['battery'] != null) {
      items.add(MenuItemLabel(
        label: 'Peer Battery: ${state['battery']}% ${state['batteryCharging'] == true ? "(Charging)" : ""}',
        enabled: false,
      ));
    }

    items.addAll([
      MenuSeparator(),
      MenuItemCheckbox(
        label: 'Discovery Enabled',
        checked: state['discovery'] == true,
        onClicked: (menuItem) => onAction('toggle_discovery', !menuItem.checked),
      ),
      MenuItemCheckbox(
        label: 'Sync Paused',
        checked: state['paused'] == true,
        onClicked: (menuItem) => onAction('toggle_pause', !menuItem.checked),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Find My Phone',
        onClicked: (menuItem) => onAction('find_phone', null),
      ),
      MenuSeparator(),
      MenuItemLabel(
        label: 'Quit',
        onClicked: (menuItem) => onAction('quit', null),
      ),
    ]);

    await _menu.buildFrom(items);
    await _systemTray.setContextMenu(_menu);
  }
}
