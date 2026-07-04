import 'dart:io';
import 'package:flutter/material.dart';
import '../models/card_model.dart' as models;

class ImageCard extends StatelessWidget {
  final models.Card card;
  final ValueChanged<String> onContentChanged;
  final VoidCallback? onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const ImageCard({
    super.key,
    required this.card,
    required this.onContentChanged,
    this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
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
          const Icon(Icons.image_outlined, size: 16, color: Color(0xFF64748B)),
          const SizedBox(width: 6),
          const Text('Image', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          const Spacer(),
          if (hasImage)
            _actionBtn(Icons.link_off, () => onContentChanged('')),
          if (onMoveUp != null) _actionBtn(Icons.arrow_upward, onMoveUp!),
          if (onMoveDown != null) _actionBtn(Icons.arrow_downward, onMoveDown!),
          if (onDelete != null) _actionBtn(Icons.delete_outline, onDelete!, color: const Color(0xFFF87171)),
        ],
      ),
    );
  }

  Widget _buildImage() {
    final content = card.content;
    final isFile = content.startsWith('/') || content.startsWith('file://');
    final path = content.startsWith('file://') ? content.substring(7) : content;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: isFile
            ? Image.file(
                File(path),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _buildError(),
              )
            : Image.network(
                content,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _buildError(),
              ),
      ),
    );
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
    // Show a dialog to enter image URL or path
    final controller = TextEditingController(text: card.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        title: const Text('Add Image', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter image URL or file path',
            hintStyle: TextStyle(color: Colors.grey),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              onContentChanged(controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('Add', style: TextStyle(color: Color(0xFF818CF8))),
          ),
        ],
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
