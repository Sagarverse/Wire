import 'dart:ui';

import 'package:flutter/material.dart';

class LiquidGlassDockItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const LiquidGlassDockItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

class LiquidGlassDock extends StatelessWidget {
  final List<LiquidGlassDockItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final Axis direction;

  const LiquidGlassDock({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    this.direction = Axis.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final horizontal = direction == Axis.horizontal;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useCompact = horizontal && constraints.maxWidth < 500;

        return ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: horizontal ? 10 : 8,
                vertical: horizontal ? 8 : 10,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    (isDark ? Colors.black : Colors.white).withValues(
                      alpha: isDark ? 0.3 : 0.4,
                    ),
                    (isDark ? Colors.black26 : Colors.white38).withValues(
                      alpha: isDark ? 0.2 : 0.25,
                    ),
                  ],
                ),
                border: Border.all(
                  color: (isDark ? Colors.white : scheme.primary).withValues(alpha: isDark ? 0.15 : 0.12),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(
                      alpha: isDark ? 0.18 : 0.08,
                    ),
                    blurRadius: 24.clamp(0, double.infinity).toDouble(),
                    offset: const Offset(0, 10),
                    spreadRadius: -2, // Normalized from -4
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: isDark ? 0.3 : 0.06,
                    ),
                    blurRadius: 18.clamp(0, double.infinity).toDouble(),
                    offset: const Offset(0, 8),
                    spreadRadius: -1, // Normalized from -3
                  ),
                ],
              ),
              child: Flex(
                direction: direction,
                mainAxisSize: MainAxisSize.min,
                children: List.generate(items.length, (index) {
                  final item = items[index];
                  final selected = index == selectedIndex;

                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: horizontal ? 4 : 0,
                      vertical: horizontal ? 0 : 4,
                    ),
                    child: _DockButton(
                      item: item,
                      selected: selected,
                      horizontal: horizontal,
                      showLabel: !useCompact || selected,
                      onTap: () => onSelect(index),
                    ),
                  );
                }),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DockButton extends StatelessWidget {
  final LiquidGlassDockItem item;
  final bool selected;
  final bool horizontal;
  final bool showLabel;
  final VoidCallback onTap;

  const _DockButton({
    required this.item,
    required this.selected,
    required this.horizontal,
    required this.showLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedScale(
      scale: selected ? 1.15 : 1.0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.elasticOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: selected
              ? scheme.primary.withValues(alpha: isDark ? 0.35 : 0.2)
              : Colors.transparent,
          border: selected
              ? Border.all(color: (isDark ? Colors.white : scheme.primary).withValues(alpha: 0.3), width: 1.2)
              : null,
          boxShadow: [
            if (selected)
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.2),
                blurRadius: 15.clamp(0, double.infinity).toDouble(),
                spreadRadius: -1, // Normalized from -2
              ),
          ],
        ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontal ? 14 : 12,
            vertical: horizontal ? 10 : 12,
          ),
          child: horizontal
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      selected ? item.selectedIcon : item.icon,
                      size: 20,
                      color: selected
                          ? scheme.primary
                          : scheme.onSurface.withValues(alpha: 0.72),
                    ),
                    if (showLabel) ...[
                      const SizedBox(width: 8),
                      Text(
                        item.label,
                        style: TextStyle(
                          color: selected
                              ? scheme.primary
                              : scheme.onSurface.withValues(alpha: 0.7),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                )
              : Tooltip(
                  message: item.label,
                  child: Icon(
                    selected ? item.selectedIcon : item.icon,
                    size: 22,
                    color: selected
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
        ),
        ),
      ),
    );
  }
}
