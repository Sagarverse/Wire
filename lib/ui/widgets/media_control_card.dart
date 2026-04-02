import 'package:flutter/material.dart';
import 'glass_card.dart';

class MediaControlCard extends StatelessWidget {
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onVolumeUp;
  final VoidCallback onVolumeDown;
  final VoidCallback onMute;

  const MediaControlCard({
    super.key,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onVolumeUp,
    required this.onVolumeDown,
    required this.onMute,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GlassCard(
      accent: scheme.tertiary,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.music_note_rounded, color: scheme.tertiary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Media Controls',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildIconButton(context, Icons.skip_previous, onPrevious),
              _buildIconButton(
                context,
                Icons.play_arrow,
                onPlayPause,
                size: 32,
                isPrimary: true,
              ),
              _buildIconButton(context, Icons.skip_next, onNext),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: scheme.onSurface.withValues(alpha: 0.15)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildIconButton(context, Icons.volume_down, onVolumeDown),
              _buildIconButton(context, Icons.volume_off, onMute),
              _buildIconButton(context, Icons.volume_up, onVolumeUp),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton(
    BuildContext context,
    IconData icon,
    VoidCallback onPressed, {
    double size = 24,
    bool isPrimary = false,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          padding: EdgeInsets.all(isPrimary ? 12 : 8),
          decoration: BoxDecoration(
            color: isPrimary
                ? scheme.tertiary.withValues(alpha: 0.24)
                : scheme.onSurface.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: isPrimary
                ? scheme.tertiary
                : scheme.onSurface.withValues(alpha: 0.7),
            size: size,
          ),
        ),
      ),
    );
  }
}
