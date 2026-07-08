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

  bool _isImage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return true;
    }
    if (trimmed.startsWith('/') || trimmed.startsWith('file://')) {
      return true;
    }
    if (trimmed.contains('.') && (
        trimmed.endsWith('.png') ||
        trimmed.endsWith('.jpg') ||
        trimmed.endsWith('.jpeg') ||
        trimmed.endsWith('.gif') ||
        trimmed.endsWith('.webp') ||
        trimmed.endsWith('.svg')
    )) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final trimmed = emoji.trim();

    if (!_isImage(trimmed)) {
      return Icon(
        Icons.description_outlined,
        size: size,
        color: const Color(0xFFCBD5E1),
      );
    }

    Widget imageWidget;
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      imageWidget = Image.network(
        trimmed,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildDefaultIcon(),
      );
    } else if (trimmed.startsWith('/') || trimmed.startsWith('file://')) {
      final path = trimmed.startsWith('file://') ? trimmed.substring(7) : trimmed;
      imageWidget = Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildDefaultIcon(),
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
                errorBuilder: (_, __, ___) => _buildDefaultIcon(),
              ),
            );
          }
          return _buildDefaultIcon();
        },
      );
    } else {
      imageWidget = _buildDefaultIcon();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.25),
      child: imageWidget,
    );
  }

  Widget _buildDefaultIcon() {
    return Icon(
      Icons.description_outlined,
      size: size,
      color: const Color(0xFFCBD5E1),
    );
  }
}
