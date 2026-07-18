import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../models/card_model.dart' as models;
import '../utils/markdown_utils.dart';

class ReadingScreen extends StatelessWidget {
  final models.Card card;
  final int cardIndex;

  const ReadingScreen({
    super.key,
    required this.card,
    required this.cardIndex,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        title: Text(
          'Block #$cardIndex',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Theme(
                data: Theme.of(context).copyWith(
                  cardColor: const Color(0xFF1D1E22),
                  canvasColor: const Color(0xFF1D1E22),
                  colorScheme: Theme.of(context).colorScheme.copyWith(
                    surface: const Color(0xFF1D1E22),
                    surfaceVariant: const Color(0xFF1D1E22),
                    onSurface: const Color(0xFFE2E8F0),
                    onSurfaceVariant: const Color(0xFFE2E8F0),
                  ),
                  textTheme: Theme.of(context).textTheme.copyWith(
                    bodyMedium: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 16, height: 1.8),
                  ),
                ),
                child: GptMarkdown(
                  formatMath(card.content),
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.8,
                    color: Color(0xFFE2E8F0),
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
        ),
      ),
    );
  }
}
