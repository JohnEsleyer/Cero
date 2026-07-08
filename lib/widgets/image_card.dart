import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../models/card_model.dart' as models;
import '../services/database_service.dart';

class ImageCard extends StatelessWidget {
  final models.Card card;
  final ValueChanged<String> onContentChanged;
  final VoidCallback? onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final int? cardIndex;
  final DatabaseService? dbService;

  const ImageCard({
    super.key,
    required this.card,
    required this.onContentChanged,
    this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
    this.cardIndex,
    this.dbService,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = card.content.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF2E2E2E), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, hasImage),
          hasImage ? _buildImage() : _buildPlaceholder(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool hasImage) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2E2E2E), width: 0.5)),
      ),
      child: Row(
        children: [
          if (cardIndex != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF818CF8).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '#$cardIndex',
                style: const TextStyle(
                  fontSize: 9,
                  color: Color(0xFF818CF8),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          const Icon(Icons.image_outlined, size: 16, color: Color(0xFF64748B)),
          const SizedBox(width: 6),
          const Text('Image', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          const Spacer(),
          if (hasImage)
            IconButton(
              icon: const Icon(Icons.broken_image_outlined, size: 16, color: Color(0xFF64748B)),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => onContentChanged(''),
              tooltip: 'Clear Image',
            ),
          if (onMoveUp != null) _actionBtn(Icons.arrow_upward, onMoveUp!),
          if (onMoveDown != null) _actionBtn(Icons.arrow_downward, onMoveDown!),
          if (onDelete != null) _actionBtn(Icons.delete_outline, onDelete!, color: const Color(0xFFF87171)),
        ],
      ),
    );
  }

  Widget _buildImage() {
    final content = card.content;
    if (content.startsWith('http://') || content.startsWith('https://')) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            content,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _buildError(),
          ),
        ),
      );
    }

    final isAbsolute = content.startsWith('/') || content.startsWith('file://');
    if (isAbsolute) {
      final path = content.startsWith('file://') ? content.substring(7) : content;
      return Padding(
        padding: const EdgeInsets.all(8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _buildError(),
          ),
        ),
      );
    }

    if (dbService != null) {
      return FutureBuilder<String?>(
        future: dbService!.getImagePath(content),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 100,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final path = snapshot.data;
          if (path != null && File(path).existsSync()) {
            return Padding(
              padding: const EdgeInsets.all(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => _buildError(),
                ),
              ),
            );
          }
          return _buildError();
        },
      );
    }

    return _buildError();
  }

  Widget _buildError() {
    return Container(
      height: 100,
      alignment: Alignment.center,
      child: const Text('Failed to load image', style: TextStyle(color: Color(0xFFF87171), fontSize: 12)),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return InkWell(
      onTap: () => _pickImage(context),
      child: Container(
        height: 100,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_photo_alternate_outlined, size: 28, color: Color(0xFF4A4A4A)),
            const SizedBox(height: 6),
            Text(
              'Tap to add image',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  void _pickImage(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF202020),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Add Image',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 14),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF818CF8)),
              title: const Text('Choose from System/Gallery', style: TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  final result = await FilePicker.platform.pickFiles(type: FileType.image);
                  if (result != null && result.files.single.path != null) {
                    final file = File(result.files.single.path!);
                    final bytes = await file.readAsBytes();
                    final name = result.files.single.name;
                    if (dbService != null) {
                      final filename = await dbService!.saveImage(bytes, name);
                      onContentChanged(filename);
                    } else {
                      onContentChanged(file.path);
                    }
                  }
                } catch (e) {
                  debugPrint('Error picking image: $e');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.link, color: Color(0xFF818CF8)),
              title: const Text('Enter Image URL', style: TextStyle(color: Colors.white, fontSize: 13)),
              onTap: () {
                Navigator.pop(ctx);
                final controller = TextEditingController(text: card.content.startsWith('http') ? card.content : '');
                showDialog(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    backgroundColor: const Color(0xFF202020),
                    title: const Text('Add Image URL', style: TextStyle(color: Colors.white, fontSize: 14)),
                    content: TextField(
                      controller: controller,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Enter image URL (http://... or https://...)',
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 12),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF3E3E3E))),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF818CF8))),
                      ),
                      autofocus: true,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                      ),
                      TextButton(
                        onPressed: () {
                          onContentChanged(controller.text.trim());
                          Navigator.pop(dialogCtx);
                        },
                        child: const Text('Add', style: TextStyle(color: Color(0xFF818CF8))),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, VoidCallback onPressed, {Color? color}) {
    return IconButton(
      icon: Icon(icon, size: 16),
      padding: const EdgeInsets.all(2),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: onPressed,
      color: color ?? const Color(0xFF64748B),
    );
  }
}
