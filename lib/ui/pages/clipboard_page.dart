import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../controllers/clipboard_controller.dart';
import '../../models/clipboard_item.dart';
import '../../widgets/liquid_background.dart';

class ClipboardPage extends StatefulWidget {
  final EdgeInsets? padding;
  const ClipboardPage({super.key, this.padding});

  @override
  State<ClipboardPage> createState() => _ClipboardPageState();
}

class _ClipboardPageState extends State<ClipboardPage> {
  @override
  Widget build(BuildContext context) {
    return Consumer<ClipboardController>(
      builder: (context, controller, _) {
        final scheme = Theme.of(context).colorScheme;
        final items = controller.history;

        return LiquidBackground(
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Clipboard', style: Theme.of(context).textTheme.headlineMedium)
                                .animate().fadeIn(duration: 400.ms),
                            const SizedBox(height: 2),
                            Text(
                              controller.isSyncPaused ? 'Sync paused' : '${items.length} items synced',
                              style: TextStyle(
                                color: scheme.onSurface.withValues(alpha: 0.5),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Sync toggle
                      _SyncButton(
                        isPaused: controller.isSyncPaused,
                        onToggle: () {
                          HapticFeedback.lightImpact();
                          controller.setSyncPaused(!controller.isSyncPaused);
                        },
                      ),
                      if (items.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => _showClearDialog(context, controller),
                          icon: Icon(Icons.delete_outline_rounded, size: 20),
                          style: IconButton.styleFrom(
                            foregroundColor: scheme.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Clipboard list
                Expanded(
                  child: items.isEmpty
                      ? _buildEmptyState(scheme)
                      : ListView.builder(
                          padding: widget.padding ??
                              EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).padding.bottom + 100),
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return Dismissible(
                              key: ValueKey('${item.text.hashCode}_${item.timestamp.millisecondsSinceEpoch}'),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(Icons.delete_outline_rounded,
                                    color: Colors.redAccent.withValues(alpha: 0.6)),
                              ),
                              onDismissed: (_) {
                                HapticFeedback.mediumImpact();
                                controller.removeItem(index);
                              },
                              child: _ClipboardCard(
                                item: item,
                                onCopy: () => _copyItem(context, item),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.04),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.content_paste_rounded,
              size: 36,
              color: scheme.onSurface.withValues(alpha: 0.12),
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(duration: 2500.ms, begin: const Offset(1, 1), end: const Offset(1.06, 1.06)),
          const SizedBox(height: 20),
          Text(
            'No clipboard history',
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.4),
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Copy text on any paired device\nto see it here',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurface.withValues(alpha: 0.25),
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  void _copyItem(BuildContext context, ClipboardItem item) {
    Clipboard.setData(ClipboardData(text: item.text));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            const Text('Copied'),
          ],
        ),
        duration: const Duration(milliseconds: 800),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showClearDialog(BuildContext context, ClipboardController controller) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text('All clipboard entries will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              controller.clearHistory();
              Navigator.pop(ctx);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

// ─── Sync Button ───────────────────────────────────────────────────────────────

class _SyncButton extends StatelessWidget {
  final bool isPaused;
  final VoidCallback onToggle;

  const _SyncButton({required this.isPaused, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isPaused ? scheme.outline : const Color(0xFF34C759);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPaused ? Icons.pause_rounded : Icons.sync_rounded,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 6),
              Text(
                isPaused ? 'Paused' : 'Sync on',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Clipboard Card ────────────────────────────────────────────────────────────

class _ClipboardCard extends StatelessWidget {
  final ClipboardItem item;
  final VoidCallback onCopy;

  const _ClipboardCard({required this.item, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRemote = item.from == 'Remote';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onCopy,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surface.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Content
                Text(
                  item.text,
                  style: const TextStyle(fontSize: 13, height: 1.4),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                // Footer
                Row(
                  children: [
                    if (isRemote)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.phone_android_rounded, size: 10, color: scheme.primary),
                            const SizedBox(width: 3),
                            Text(
                              'Remote',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: scheme.primary),
                            ),
                          ],
                        ),
                      ),
                    if (isRemote) const SizedBox(width: 8),
                    Text(
                      _timeAgo(item.timestamp),
                      style: TextStyle(fontSize: 10, color: scheme.onSurface.withValues(alpha: 0.3)),
                    ),
                    const Spacer(),
                    Icon(Icons.content_copy_rounded, size: 13, color: scheme.onSurface.withValues(alpha: 0.2)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
