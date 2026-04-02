import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class FilePreviewPage extends StatelessWidget {
  final String filePath;

  const FilePreviewPage({super.key, required this.filePath});

  @override
  Widget build(BuildContext context) {
    final file = File(filePath);
    final ext = p.extension(filePath).toLowerCase();
    final name = p.basename(filePath);

    Widget content;

    if (!file.existsSync()) {
      content = const Center(
        child: Text('File not found', style: TextStyle(color: Colors.white)),
      );
    } else if (['.png', '.jpg', '.jpeg', '.gif', '.webp'].contains(ext)) {
      content = Center(child: InteractiveViewer(child: Image.file(file)));
    } else if ([
      '.txt',
      '.md',
      '.json',
      '.dart',
      '.py',
      '.js',
      '.ts',
      '.html',
      '.css',
      '.xml',
      '.yaml',
      '.yml',
    ].contains(ext)) {
      try {
        final text = file.readAsStringSync();
        content = SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
          ),
        );
      } catch (e) {
        content = Center(
          child: Text(
            'Could not read text file: $e',
            style: const TextStyle(color: Colors.white70),
          ),
        );
      }
    } else {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.insert_drive_file,
              size: 80,
              color: Colors.white38,
            ),
            const SizedBox(height: 16),
            Text(
              'No preview available for $ext files.',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: Text(name), backgroundColor: Colors.black),
      body: content,
    );
  }
}
