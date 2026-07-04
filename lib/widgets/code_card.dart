import 'package:flutter/material.dart';
import '../models/card_model.dart' as models;

class CodeCard extends StatefulWidget {
  final models.Card card;
  final ValueChanged<String> onContentChanged;
  final VoidCallback? onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const CodeCard({
    super.key,
    required this.card,
    required this.onContentChanged,
    this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  State<CodeCard> createState() => _CodeCardState();
}

class _CodeCardState extends State<CodeCard> {
  bool _isEditing = false;
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
    if (oldWidget.card.id != widget.card.id ||
        (!_isEditing && oldWidget.card.content != widget.card.content)) {
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

  void _save() {
    final combined = '$_lang\n${_controller.text}';
    widget.onContentChanged(combined);
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
        border: Border(
          bottom: BorderSide(color: Color(0xFF2E2E2E), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              setState(() {
                if (_isEditing) {
                  _save();
                }
                _isEditing = !_isEditing;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _isEditing
                    ? const Color(0xFF818CF8).withOpacity(0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(
                    _isEditing ? Icons.check_circle_outline : Icons.edit_outlined,
                    size: 16,
                    color: _isEditing
                        ? const Color(0xFF818CF8)
                        : const Color(0xFF64748B),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _isEditing ? 'Done' : 'Edit',
                    style: TextStyle(
                      color: _isEditing
                          ? const Color(0xFF818CF8)
                          : const Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isEditing) ...[
            const SizedBox(width: 12),
            DropdownButton<String>(
              value: _lang,
              dropdownColor: const Color(0xFF202020),
              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF818CF8), size: 16),
              underline: const SizedBox(),
              style: const TextStyle(color: Color(0xFF818CF8), fontSize: 12, fontWeight: FontWeight.bold),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _lang = val;
                  });
                  _save();
                }
              },
              items: const [
                DropdownMenuItem(value: 'javascript', child: Text('JS')),
                DropdownMenuItem(value: 'python', child: Text('PYTHON')),
                DropdownMenuItem(value: 'html', child: Text('HTML')),
                DropdownMenuItem(value: 'css', child: Text('CSS')),
                DropdownMenuItem(value: 'go', child: Text('GO')),
                DropdownMenuItem(value: 'dart', child: Text('DART')),
                DropdownMenuItem(value: 'json', child: Text('JSON')),
                DropdownMenuItem(value: 'bash', child: Text('BASH')),
              ],
            ),
          ],
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

  Widget _buildEditor() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TextField(
        controller: _controller,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        style: const TextStyle(
          fontSize: 13,
          height: 1.5,
          fontFamily: 'monospace',
          color: Color(0xFFE2E8F0),
        ),
        decoration: const InputDecoration(
          hintText: 'Write code here...',
          hintStyle: TextStyle(color: Color(0xFF4A4A4A)),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (_) => _save(),
      ),
    );
  }

  Widget _buildPreview() {
    return InkWell(
      onDoubleTap: () {
        setState(() {
          _isEditing = true;
        });
      },
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
          text: '// Empty code block...',
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