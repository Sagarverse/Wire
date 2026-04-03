import 'package:flutter/material.dart';
import 'glass_card.dart';

class StatusDash extends StatelessWidget {
  final String deviceName;
  final int batteryLevel;
  final bool isCharging;
  final String? peerName;
  final bool isPeerConnected;
  final int? remoteBattery;
  final bool? remoteIsCharging;
  final int? pingMs;
  final bool isSyncing;

  final VoidCallback? onReconnect;
  final VoidCallback? onDevicesTapped;

  const StatusDash({
    super.key,
    required this.deviceName,
    required this.batteryLevel,
    required this.isCharging,
    this.peerName,
    this.isPeerConnected = false,
    this.remoteBattery,
    this.remoteIsCharging,
    this.pingMs,
    this.isSyncing = false,
    this.onReconnect,
    this.onDevicesTapped,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Top row: local battery + peer connection
        Row(
          children: [
            // Local Battery Card
            Expanded(
              child: GlassCard(
                accent: scheme.primary,
                padding: const EdgeInsets.all(15),
                child: Row(
                  children: [
                    Icon(
                      isCharging
                          ? Icons.battery_charging_full
                          : _getBatteryIcon(batteryLevel),
                      color: _getBatteryColor(context, batteryLevel),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$batteryLevel%',
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          deviceName,
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.56),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GlassCard(
                accent: scheme.secondary,
                padding: EdgeInsets.zero,
                child: InkWell(
                  onTap: onDevicesTapped,
                  onLongPress: isPeerConnected ? onReconnect : null,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              isPeerConnected ? Icons.devices_rounded : Icons.add_circle_outline_rounded,
                              color: isPeerConnected ? scheme.primary : scheme.onSurface.withValues(alpha: 0.4),
                              size: 20,
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isPeerConnected ? (peerName ?? 'Connected') : 'Pair Device',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: scheme.onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                isPeerConnected ? (isSyncing ? 'Syncing...' : 'Idle') : 'Not linked',
                                style: TextStyle(
                                  color: scheme.onSurface.withValues(alpha: 0.46),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        // Remote battery row (only when connected + data available)
        if (isPeerConnected && remoteBattery != null) ...[
          const SizedBox(height: 10),
          GlassCard(
            accent: scheme.tertiary,
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            child: Row(
              children: [
                Icon(
                  (remoteIsCharging ?? false)
                      ? Icons.battery_charging_full
                      : _getBatteryIcon(remoteBattery!),
                  color: _getBatteryColor(context, remoteBattery!),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Remote: $remoteBattery%${(remoteIsCharging ?? false) ? ' ⚡' : ''}',
                  style: TextStyle(
                    color: _getBatteryColor(context, remoteBattery!),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                _BatteryBar(
                  level: remoteBattery!,
                  isCharging: remoteIsCharging ?? false,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  IconData _getBatteryIcon(int level) {
    if (level > 80) return Icons.battery_full;
    if (level > 60) return Icons.battery_5_bar;
    if (level > 40) return Icons.battery_3_bar;
    if (level > 20) return Icons.battery_2_bar;
    return Icons.battery_1_bar;
  }

  Color _getBatteryColor(BuildContext context, int level) {
    final scheme = Theme.of(context).colorScheme;
    if (level > 50) return scheme.tertiary;
    if (level > 20) return const Color(0xFFF59E0B);
    return scheme.error;
  }
}

class _BatteryBar extends StatelessWidget {
  final int level;
  final bool isCharging;
  final bool isDark;
  const _BatteryBar({required this.level, required this.isCharging, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = level > 50
      ? scheme.tertiary
      : level > 20
        ? const Color(0xFFF59E0B)
        : scheme.error;
    return SizedBox(
      width: 80,
      height: 10,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          FractionallySizedBox(
            widthFactor: level / 100,
            child: Container(
              decoration: BoxDecoration(
                color: isCharging
                    ? const Color(0xFFFBBF24)
                    : color,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Animated pulse ring shown when syncing is active.
class _SyncPulse extends StatefulWidget {
  @override
  State<_SyncPulse> createState() => _SyncPulseState();
}

class _SyncPulseState extends State<_SyncPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
    _scale = Tween(
      begin: 1.0,
      end: 2.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
    _opacity = Tween(
      begin: 0.6,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Transform.scale(
          scale: _scale.value,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.tertiary.withValues(alpha: _opacity.value),
            ),
          ),
        );
      },
    );
  }
}
