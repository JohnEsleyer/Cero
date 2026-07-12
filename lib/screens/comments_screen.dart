import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../models/card_model.dart' as models;
import '../services/server_service.dart';
import '../widgets/card_column.dart';
import '../utils/markdown_utils.dart';

class CommentsScreen extends StatefulWidget {
  final models.Card card;
  final int cardIndex;
  final ServerService serverService;
  final VoidCallback onCommentsUpdated;

  const CommentsScreen({
    super.key,
    required this.card,
    required this.cardIndex,
    required this.serverService,
    required this.onCommentsUpdated,
  });

  @override
  State<CommentsScreen> createState() => _CommentsScreenState();
}

class _CommentsScreenState extends State<CommentsScreen> {
  late models.Card _currentCard;
  final TextEditingController _commentController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  double? _topHeight;

  @override
  void initState() {
    super.initState();
    _currentCard = widget.card;
  }

  @override
  void dispose() {
    _commentController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;

    final meta = CardMetadata.fromJsonString(_currentCard.comment);
    final updatedComments = List<String>.from(meta.comments)..add(text);
    final newMeta = CardMetadata(color: meta.color, comments: updatedComments);
    final newMetaJson = newMeta.toJsonString();

    await widget.serverService.updateCard(
      id: _currentCard.id,
      comment: newMetaJson,
    );

    _commentController.clear();

    setState(() {
      _currentCard = _currentCard.copyWith(comment: newMetaJson);
    });

    widget.onCommentsUpdated();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _deleteComment(int index) async {
    final meta = CardMetadata.fromJsonString(_currentCard.comment);
    if (index < 0 || index >= meta.comments.length) return;

    final updatedComments = List<String>.from(meta.comments)..removeAt(index);
    final newMeta = CardMetadata(color: meta.color, comments: updatedComments);
    final newMetaJson = newMeta.toJsonString();

    await widget.serverService.updateCard(
      id: _currentCard.id,
      comment: newMetaJson,
    );

    setState(() {
      _currentCard = _currentCard.copyWith(comment: newMetaJson);
    });

    widget.onCommentsUpdated();
  }

  @override
  Widget build(BuildContext context) {
    final meta = CardMetadata.fromJsonString(_currentCard.comment);
    final comments = meta.comments;

    return Scaffold(
      backgroundColor: const Color(0xFF191919),
      appBar: AppBar(
        backgroundColor: const Color(0xFF202020),
        elevation: 0,
        title: Text(
          'Block #${widget.cardIndex} Notes',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final double minHeight = 100.0;
                final double maxHeight = constraints.maxHeight - 100.0;
                final double clampedMaxHeight = maxHeight < minHeight ? minHeight : maxHeight;
                
                double topHeight = _topHeight ?? (constraints.maxHeight * 0.45);
                topHeight = topHeight.clamp(minHeight, clampedMaxHeight);

                return Column(
                  children: [
                    // Top Pane: Context card content
                    Container(
                      height: topHeight,
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1E1E1E),
                        border: Border(
                          bottom: BorderSide(color: Color(0xFF2C2C2C)),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              'CARD CONTENT CONTEXT',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF64748B),
                                letterSpacing: 0.8,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Container(
                              width: double.infinity,
                              margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF151515),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF2C2C2C)),
                              ),
                              child: SingleChildScrollView(
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                    cardColor: const Color(0xFF131313),
                                    canvasColor: const Color(0xFF131313),
                                    colorScheme: Theme.of(context).colorScheme.copyWith(
                                      surface: const Color(0xFF131313),
                                      surfaceVariant: const Color(0xFF131313),
                                      onSurface: const Color(0xFFCBD5E1),
                                      onSurfaceVariant: const Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  child: GptMarkdown(
                                    formatMath(_currentCard.content.trim().isEmpty
                                        ? '*Empty markdown card*'
                                        : _currentCard.content),
                                    style: const TextStyle(fontSize: 12, height: 1.5, color: Color(0xFFCBD5E1)),
                                    codeBuilder: (context, name, code, closed) {
                                      return Container(
                                        margin: const EdgeInsets.symmetric(vertical: 4),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF131313),
                                          borderRadius: BorderRadius.circular(6),
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
                                                fontSize: 11,
                                                height: 1.4,
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
                        ],
                      ),
                    ),
                    
                    // Divider drag handle
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragUpdate: (details) {
                        setState(() {
                          _topHeight = (topHeight + details.primaryDelta!).clamp(minHeight, clampedMaxHeight);
                        });
                      },
                      child: Container(
                        width: double.infinity,
                        height: 24,
                        color: const Color(0xFF191919),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: double.infinity,
                              height: 1,
                              color: const Color(0xFF2C2C2C),
                            ),
                            Container(
                              width: 48,
                              height: 8,
                              decoration: BoxDecoration(
                                color: const Color(0xFF202020),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFF3E3E3E), width: 1),
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(width: 2, height: 2, color: Colors.grey),
                                    const SizedBox(width: 2),
                                    Container(width: 2, height: 2, color: Colors.grey),
                                    const SizedBox(width: 2),
                                    Container(width: 2, height: 2, color: Colors.grey),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    
                    // Bottom Pane: Comments ListView
                    Expanded(
                      child: comments.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 44,
                                    color: Color(0xFF3F3F46),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'No notes added yet',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Add context notes for this block below.',
                                    style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: comments.length,
                              itemBuilder: (context, idx) {
                                final comment = comments[idx];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF202020),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFF2E2E2E)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Padding(
                                        padding: EdgeInsets.only(top: 2),
                                        child: Icon(
                                          Icons.notes_rounded,
                                          size: 14,
                                          color: Color(0xFF818CF8),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          comment,
                                          style: const TextStyle(
                                            fontSize: 12.5,
                                            color: Color(0xFFCBD5E1),
                                            height: 1.4,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 15,
                                          color: Colors.redAccent,
                                        ),
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        onPressed: () => _deleteComment(idx),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: const BoxDecoration(
                color: Color(0xFF202020),
                border: Border(
                  top: BorderSide(color: Color(0xFF2C2C2C)),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        hintText: 'Type additional note info...',
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 13),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _addComment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF818CF8),
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(10),
                      minimumSize: Size.zero,
                    ),
                    child: const Icon(Icons.send_rounded, size: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
