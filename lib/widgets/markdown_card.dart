import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../models/card_model.dart' as models;
import '../screens/reading_screen.dart';
import '../utils/markdown_utils.dart';

const int _previewWordLimit = 100;

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

  void _openReadingScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReadingScreen(
          card: widget.card,
          cardIndex: widget.cardIndex,
        ),
      ),
    );
  }

  String _truncateContent(String content) {
    final RegExp wordRegExp = RegExp(r'\S+');
    final matches = wordRegExp.allMatches(content);
    if (matches.length <= _previewWordLimit) return content;
    final lastMatch = matches.elementAt(_previewWordLimit - 1);
    return '${content.substring(0, lastMatch.end)}...';
  }

  @override
  Widget build(BuildContext context) {
    final Color resolvedText = widget.textColor ?? const Color(0xFFCBD5E1);
    final Color resolvedMuted = widget.textMutedColor ?? const Color(0xFF71717A);
    final content = _controller.text;
    final needsTruncation = content.trim().split(RegExp(r'\s+')).length > _previewWordLimit;

    if (content.trim().isEmpty) {
      return InkWell(
        onTap: _openReadingScreen,
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: Text(
              'Empty card... Use the Edit button to write content.',
              style: TextStyle(
                color: Color(0xFF4A4A4A),
                fontStyle: FontStyle.italic,
                fontSize: 14,
                fontFamily: 'serif',
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: _openReadingScreen,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, needsTruncation ? 4 : 12),
            child: Theme(
              data: Theme.of(context).copyWith(
                cardColor: const Color(0xFF1D1E22),
                canvasColor: const Color(0xFF1D1E22),
                colorScheme: Theme.of(context).colorScheme.copyWith(
                  surface: const Color(0xFF1D1E22),
                  surfaceVariant: const Color(0xFF1D1E22),
                  onSurface: resolvedText,
                  onSurfaceVariant: resolvedText,
                ),
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
                formatMath(needsTruncation ? _truncateContent(content) : content),
                style: TextStyle(
                  fontSize: 16,
                  height: 1.8,
                  color: resolvedText,
                  fontFamily: 'serif',
                ),
                codeBuilder: (context, name, code, closed) {
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D1E22),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF2C2C2C)),
                    ),
                    width: double.infinity,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: RichText(
                        text: TextSpan(
                          children: highlightCode(code, name),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        if (needsTruncation)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: GestureDetector(
              onTap: _openReadingScreen,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF818CF8).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF818CF8).withOpacity(0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.chrome_reader_mode_outlined, size: 13, color: Color(0xFF818CF8)),
                    const SizedBox(width: 6),
                    const Text(
                      'Read Fullscreen',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF818CF8),
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.arrow_forward, size: 12, color: Color(0xFF818CF8)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
