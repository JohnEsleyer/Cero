import 'dart:io';
import 'package:flutter/material.dart';
import '../services/database_service.dart';

class PageIcon extends StatelessWidget {
  final String emoji;
  final double size;
  final DatabaseService? dbService;

  const PageIcon({
    super.key,
    required this.emoji,
    this.size = 16,
    this.dbService,
  });

  bool _isEmoji(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return true;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return false;
    }
    if (trimmed.startsWith('/') || trimmed.startsWith('file://')) {
      return false;
    }
    if (trimmed.contains('.') && (
        trimmed.endsWith('.png') ||
        trimmed.endsWith('.jpg') ||
        trimmed.endsWith('.jpeg') ||
        trimmed.endsWith('.gif') ||
        trimmed.endsWith('.webp') ||
        trimmed.endsWith('.svg')
    )) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = emoji.trim();
    if (_isEmoji(trimmed)) {
      return Text(
        trimmed.isEmpty ? '📝' : trimmed,
        style: TextStyle(fontSize: size, height: 1.1),
      );
    }

    Widget imageWidget;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      imageWidget = Image.network(
        trimmed,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildErrorIcon(),
      );
    } else if (trimmed.startsWith('/') || trimmed.startsWith('file://')) {
      final path = trimmed.startsWith('file://') ? trimmed.substring(7) : trimmed;
      imageWidget = Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildErrorIcon(),
      );
    } else if (dbService != null) {
      return FutureBuilder<String?>(
        future: dbService!.getImagePath(trimmed),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return SizedBox(
              width: size,
              height: size,
              child: Padding(
                padding: EdgeInsets.all(size * 0.1),
                child: const CircularProgressIndicator(strokeWidth: 1),
              ),
            );
          }
          final path = snapshot.data;
          if (path != null && File(path).existsSync()) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.25),
              child: Image.file(
                File(path),
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildErrorIcon(),
              ),
            );
          }
          return _buildErrorIcon();
        },
      );
    } else {
      imageWidget = _buildErrorIcon();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.25),
      child: imageWidget,
    );
  }

  Widget _buildErrorIcon() {
    return Icon(
      Icons.broken_image_outlined,
      size: size,
      color: Colors.grey,
    );
  }
}
