import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../models/card_model.dart' as models;
import 'immersive_markdown_editor.dart';

class MarkdownCard extends StatefulWidget {
  final models.Card card;
  final ValueChanged<String> onContentChanged;
  final int cardIndex;

  final Color? textColor;
  final Color? textMutedColor;

  const MarkdownCard({
    super.key,
    required this.card,
    required this.onContentChanged,
    required this.cardIndex,
    this.textColor,
    this.textMutedColor,
  });

  @override
  State<MarkdownCard> createState() => _MarkdownCardState();
}

class _MarkdownCardState extends State<MarkdownCard> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.card.content);
  }

  @override
  void didUpdateWidget(MarkdownCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.id != widget.card.id || oldWidget.card.content != widget.card.content) {
      _controller.text = widget.card.content;
    }
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
        builder: (context) => ImmersiveMarkdownEditor(
          cardId: widget.card.id,
          initialContent: widget.card.content,
          onSave: (newContent) {
            _controller.text = newContent;
            widget.onContentChanged(newContent);
            setState(() {});
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color resolvedText = widget.textColor ?? const Color(0xFFCBD5E1);
    final Color resolvedMuted = widget.textMutedColor ?? const Color(0xFF71717A);
    final content = _controller.text;

    if (content.trim().isEmpty) {
      return InkWell(
        onTap: _openImmersiveEditor,
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Empty card... Tap to edit in fullscreen.',
              style: TextStyle(
                color: Color(0xFF4A4A4A),
                fontStyle: FontStyle.italic,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );
    }

    return InkWell(
      onDoubleTap: _openImmersiveEditor,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Theme(
          data: Theme.of(context).copyWith(
            textTheme: Theme.of(context).textTheme.copyWith(
              headlineLarge: TextStyle(color: resolvedText),
              headlineMedium: TextStyle(color: resolvedText),
              headlineSmall: TextStyle(color: resolvedText),
              titleLarge: TextStyle(color: resolvedText),
              titleMedium: TextStyle(color: resolvedText),
              titleSmall: TextStyle(color: resolvedText),
              bodyLarge: TextStyle(color: resolvedText),
              bodyMedium: TextStyle(color: resolvedText),
              bodySmall: TextStyle(color: resolvedText),
            ),
          ),
          child: GptMarkdown(
            content,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: resolvedText,
            ),
          ),
        ),
      ),
    );
  }
}
