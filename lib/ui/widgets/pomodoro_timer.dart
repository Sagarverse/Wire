import 'dart:async';
import 'package:flutter/material.dart';
import 'glass_card.dart';

class PomodoroTimer extends StatefulWidget {
  const PomodoroTimer({super.key});

  @override
  State<PomodoroTimer> createState() => _PomodoroTimerState();
}

class _PomodoroTimerState extends State<PomodoroTimer> {
  static const int _workDuration = 25 * 60;
  int _timeLeft = _workDuration;
  bool _isRunning = false;
  Timer? _timer;

  void _toggleTimer() {
    if (_isRunning) {
      _timer?.cancel();
      setState(() => _isRunning = false);
    } else {
      setState(() => _isRunning = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_timeLeft > 0) {
          setState(() => _timeLeft--);
        } else {
          timer.cancel();
          setState(() {
            _isRunning = false;
            _timeLeft = _workDuration;
          });
          // Play a sound or show a notification ideally.
        }
      });
    }
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _timeLeft = _workDuration;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _timeString {
    final minutes = (_timeLeft / 60).floor().toString().padLeft(2, '0');
    final seconds = (_timeLeft % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final progress = 1.0 - (_timeLeft / _workDuration);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.timer, color: Colors.amberAccent, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Focus Timer',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text(
                _timeString,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white10,
            valueColor: const AlwaysStoppedAnimation(Colors.amberAccent),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: _resetTimer,
                icon: const Icon(
                  Icons.refresh,
                  color: Colors.white54,
                  size: 18,
                ),
                label: const Text(
                  'Reset',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _toggleTimer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRunning
                      ? Colors.redAccent
                      : Colors.indigoAccent,
                  foregroundColor: Colors.white,
                ),
                icon: Icon(
                  _isRunning ? Icons.pause : Icons.play_arrow,
                  size: 18,
                ),
                label: Text(_isRunning ? 'Pause' : 'Start Focus'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
