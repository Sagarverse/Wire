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

    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
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
                (isDark ? const Color(0xFF141E30) : Colors.white).withValues(
                  alpha: isDark ? 0.82 : 0.84,
                ),
                (isDark ? const Color(0xFF0D1627) : const Color(0xFFF1F6FF))
                    .withValues(alpha: isDark ? 0.72 : 0.78),
              ],
            ),
            border: Border.all(
              color: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.16),
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: isDark ? 0.18 : 0.08),
                blurRadius: 24,
                offset: const Offset(0, 10),
                spreadRadius: -4,
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.26 : 0.08),
                blurRadius: 14,
                offset: const Offset(0, 5),
                spreadRadius: -3,
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
                  onTap: () => onSelect(index),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _DockButton extends StatelessWidget {
  final LiquidGlassDockItem item;
  final bool selected;
  final bool horizontal;
  final VoidCallback onTap;

  const _DockButton({
    required this.item,
    required this.selected,
    required this.horizontal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: selected
            ? scheme.primary.withValues(alpha: isDark ? 0.26 : 0.16)
            : Colors.transparent,
        border: selected
            ? Border.all(color: scheme.primary.withValues(alpha: 0.32))
            : null,
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
    );
  }
}