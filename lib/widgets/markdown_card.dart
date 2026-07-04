import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/card_model.dart' as models;

class MarkdownCard extends StatefulWidget {
  final models.Card card;
  final ValueChanged<String> onContentChanged;
  final VoidCallback? onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const MarkdownCard({
    super.key,
    required this.card,
    required this.onContentChanged,
    this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  State<MarkdownCard> createState() => _MarkdownCardState();
}

class _MarkdownCardState extends State<MarkdownCard> {
  bool _isEditing = false;
  late TextEditingController _controller;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.card.content);
  }

  @override
  void didUpdateWidget(MarkdownCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.id != widget.card.id) {
      _controller.text = widget.card.content;
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      widget.onContentChanged(_controller.text);
    });
  }

  void _insertMarkdown(String prefix, String suffix) {
    final text = _controller.text;
    final selection = _controller.selection;
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    final selected = text.substring(start, end);
    final newText = text.substring(0, start) + prefix + selected + suffix + text.substring(end);
    _controller.text = newText;
    final newPos = start + prefix.length + selected.length;
    _controller.selection = TextSelection.collapsed(offset: newPos);
    _save();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: _isEditing ? const Color(0xFF818CF8) : const Color(0xFF2E2E2E),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildToolbar(),
          _isEditing ? _buildEditor() : _buildPreview(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2E2E2E), width: 0.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => setState(() => _isEditing = !_isEditing),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _isEditing ? const Color(0xFF818CF8).withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                _isEditing ? Icons.visibility_outlined : Icons.edit_outlined,
                size: 16,
                color: _isEditing ? const Color(0xFF818CF8) : const Color(0xFF64748B),
              ),
            ),
          ),
          if (_isEditing) ...[
            const SizedBox(width: 4),
            _toolbarBtn(Icons.format_bold, () => _insertMarkdown('**', '**')),
            _toolbarBtn(Icons.format_italic, () => _insertMarkdown('*', '*')),
            _toolbarBtn(Icons.title, () => _insertMarkdown('# ', '')),
            _toolbarBtn(Icons.format_list_bulleted, () => _insertMarkdown('- ', '')),
            _toolbarBtn(Icons.check_box_outlined, () => _insertMarkdown('- [ ] ', '')),
            _toolbarBtn(Icons.code, () => _insertMarkdown('`', '`')),
          ],
          const Spacer(),
          if (widget.onMoveUp != null)
            _actionBtn(Icons.arrow_upward, widget.onMoveUp!),
          if (widget.onMoveDown != null)
            _actionBtn(Icons.arrow_downward, widget.onMoveDown!),
          if (widget.onDelete != null)
            _actionBtn(Icons.delete_outline, widget.onDelete!, color: const Color(0xFFF87171)),
        ],
      ),
    );
  }

  Widget _toolbarBtn(IconData icon, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, size: 16),
      padding: const EdgeInsets.all(2),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: onPressed,
      color: const Color(0xFF94A3B8),
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

  Widget _buildEditor() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _controller,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        style: const TextStyle(
          fontSize: 14,
          height: 1.6,
          fontFamily: 'monospace',
          color: Color(0xFFE2E8F0),
        ),
        decoration: const InputDecoration(
          hintText: 'Write something...',
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (_) => _save(),
      ),
    );
  }

  Widget _buildPreview() {
    final content = _controller.text;
    if (content.trim().isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text(
          'Empty card...',
          style: TextStyle(color: Color(0xFF4A4A4A), fontStyle: FontStyle.italic, fontSize: 13),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: MarkdownBody(
        data: content,
        selectable: true,
        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
          p: const TextStyle(fontSize: 14, height: 1.6, color: Color(0xFFCBD5E1)),
          h1: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.8, color: Colors.white),
          h2: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.8, color: Colors.white),
          h3: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, height: 1.8, color: Colors.white),
          code: const TextStyle(fontFamily: 'monospace', fontSize: 12, backgroundColor: Color(0xFF1A1A1A)),
        ),
      ),
    );
  }
}
