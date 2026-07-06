
import 'package:flutter/material.dart';
import '../models/card_model.dart' as models;
import 'immersive_code_editor.dart';

class CodeCard extends StatefulWidget {
  final models.Card card;
  final ValueChanged<String> onContentChanged;
  final VoidCallback? onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final int? cardIndex;

  const CodeCard({
    super.key,
    required this.card,
    required this.onContentChanged,
    this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
    this.cardIndex,
  });

  @override
  State<CodeCard> createState() => _CodeCardState();
}

class _CodeCardState extends State<CodeCard> {
  late TextEditingController _controller;
  String _lang = 'javascript';
  String _codeText = '';

  @override
  void initState() {
    super.initState();
    _parseContent();
  }

  @override
  void didUpdateWidget(CodeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.id != widget.card.id || oldWidget.card.content != widget.card.content) {
      _parseContent();
    }
  }

  void _parseContent() {
    final raw = widget.card.content;
    if (raw.contains('\n')) {
      final idx = raw.indexOf('\n');
      _lang = raw.substring(0, idx).trim().toLowerCase();
      _codeText = raw.substring(idx + 1);
    } else {
      _lang = 'javascript';
      _codeText = raw;
    }
    _controller = TextEditingController(text: _codeText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openImmersiveEditor() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImmersiveCodeEditor(
          cardId: widget.card.id,
          initialContent: widget.card.content,
          onSave: (newContent) {
            widget.onContentChanged(newContent);
            setState(() {
              _parseContent();
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(
          color: Color(0xFF2E2E2E),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildToolbar(),
          _buildPreview(),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF2E2E2E), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          if (widget.cardIndex != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF818CF8).withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '#${widget.cardIndex}',
                style: const TextStyle(
                  fontSize: 9,
                  color: Color(0xFF818CF8),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          GestureDetector(
            onTap: _openImmersiveEditor,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF818CF8).withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.edit_outlined,
                    size: 16,
                    color: Color(0xFF818CF8),
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Edit Fullscreen',
                    style: TextStyle(
                      color: Color(0xFF818CF8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          if (widget.onMoveUp != null)
            _actionBtn(Icons.arrow_upward, widget.onMoveUp!),
          if (widget.onMoveDown != null)
            _actionBtn(Icons.arrow_downward, widget.onMoveDown!),
          if (widget.onDelete != null)
            _actionBtn(
              Icons.delete_outline,
              widget.onDelete!,
              color: const Color(0xFFF87171),
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

  Widget _buildPreview() {
    return InkWell(
      onDoubleTap: _openImmersiveEditor,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: const BoxDecoration(
          color: Color(0xFF131313),
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(8),
            bottomRight: Radius.circular(8),
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              right: 0,
              child: Text(
                _lang.toUpperCase(),
                style: const TextStyle(
                  color: Color(0xFF818CF8),
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: RichText(
                text: TextSpan(
                  children: _highlight(_codeText, _lang),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<TextSpan> _highlight(String code, String lang) {
    if (code.isEmpty) {
      return [
        const TextSpan(
          text: '// Empty code block... Double tap to edit.',
          style: TextStyle(color: Color(0xFF64748B), fontStyle: FontStyle.italic),
        )
      ];
    }
    
    final List<TextSpan> spans = [];
    final keywords = {
      'function', 'return', 'if', 'else', 'for', 'while', 'const', 'let', 'var',
      'import', 'class', 'void', 'final', 'def', 'package', 'func', 'interface'
    };
    
    final regex = RegExp(
      r'("(?:\\.|[^"\\])*"|\x27(?:\\.|[^\x27\\])*\x27)|(\/\/[^\n]*)|(\b\w+\b)|([^\w\x22\x27\/]+|\/)',
      multiLine: true,
    );
    
    final matches = regex.allMatches(code);
    for (final match in matches) {
      final str = match.group(1);
      final comment = match.group(2);
      final word = match.group(3);
      final other = match.group(4);
      
      if (str != null) {
        spans.add(TextSpan(text: str, style: const TextStyle(color: Color(0xFF34D399))));
      } else if (comment != null) {
        spans.add(TextSpan(text: comment, style: const TextStyle(color: Color(0xFF94A3B8), fontStyle: FontStyle.italic)));
      } else if (word != null) {
        if (keywords.contains(word)) {
          spans.add(TextSpan(text: word, style: const TextStyle(color: Color(0xFFF472B6), fontWeight: FontWeight.bold)));
        } else {
          spans.add(TextSpan(text: word, style: const TextStyle(color: Color(0xFFE2E8F0))));
        }
      } else if (other != null) {
        spans.add(TextSpan(text: other, style: const TextStyle(color: Color(0xFFCBD5E1))));
      }
    }
    
    return spans;
  }
}