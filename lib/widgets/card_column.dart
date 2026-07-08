import 'dart:math';
import 'package:flutter/material.dart';
import '../models/page_model.dart';
import '../models/card_model.dart' as models;
import '../services/database_service.dart';
import '../services/server_service.dart';
import 'markdown_card.dart';
import 'image_card.dart';
import 'subpage_link_card.dart';
import 'code_card.dart'; 
import 'sites_card.dart'; 

String _generateId() {
  final rand = Random.secure();
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  return List.generate(12, (_) => chars[rand.nextInt(chars.length)]).join();
}

class CardColumn extends StatefulWidget {
  final List<models.Card> cards;
  final List<DbPage> allPages;
  final DbPage selectedPage;
  final ValueChanged<DbPage> onNavigateToPage;
  final Future<void> Function(String cardId, String content) onCardUpdated;
  final Future<void> Function(String pageId, String type, String content) onCardAdded;
  final Future<void> Function(String cardId) onCardDeleted;
  final Future<void> Function(List<String> cardIds) onCardsReordered;
  final Future<DbPage?> Function(String parentId)? onCreateNewPage;
  final ScrollController? scrollController;
  final DatabaseService? dbService;
  final ServerService serverService;

  const CardColumn({
    super.key,
    required this.cards,
    required this.allPages,
    required this.selectedPage,
    required this.onNavigateToPage,
    required this.onCardUpdated,
    required this.onCardAdded,
    required this.onCardDeleted,
    required this.onCardsReordered,
    required this.serverService,
    this.onCreateNewPage,
    this.scrollController,
    this.dbService,
  });

  @override
  State<CardColumn> createState() => _CardColumnState();
}

class _CardColumnState extends State<CardColumn> {
  bool _showScrollToBottom = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_scrollListener);
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_scrollListener);
    super.dispose();
  }

  void _scrollListener() {
    final sc = widget.scrollController;
    if (sc == null || !sc.hasClients) {
      if (_showScrollToBottom) setState(() => _showScrollToBottom = false);
      return;
    }
    final maxScroll = sc.position.maxScrollExtent;
    final currentScroll = sc.position.pixels;
    final threshold = 200.0;
    final shouldShow = maxScroll > 400 && (maxScroll - currentScroll) > threshold;
    if (shouldShow != _showScrollToBottom) {
      setState(() => _showScrollToBottom = shouldShow);
    }
  }

  void _openCommentsBottomSheet(models.Card card) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF141416),
      isScrollControlled: true,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _CommentsBottomSheetContent(
        initialCard: card,
        serverService: widget.serverService,
        onCardUpdated: widget.onCardUpdated,
      ),
    );
  }

  int _cardIndex(models.Card card) => widget.cards.indexWhere((c) => c.id == card.id);

  void _moveCard(int fromIndex, int direction) {
    final toIndex = fromIndex + direction;
    if (toIndex < 0 || toIndex >= widget.cards.length) return;
    final newCards = List<models.Card>.from(widget.cards);
    final item = newCards.removeAt(fromIndex);
    newCards.insert(toIndex, item);
    widget.onCardsReordered(newCards.map((c) => c.id).toList());
  }

  void _onReorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final newCards = List<models.Card>.from(widget.cards);
    final item = newCards.removeAt(oldIndex);
    newCards.insert(newIndex > oldIndex ? newIndex - 1 : newIndex, item);
    widget.onCardsReordered(newCards.map((c) => c.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.note_alt_outlined, size: 64, color: Color(0xFF4A4A4A)),
              const SizedBox(height: 16),
              const Text(
                'This page is empty',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add blocks to start writing and organizing your thoughts.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  _emptyPageBlockTrigger('Markdown', 'markdown', Icons.text_fields),
                  _emptyPageBlockTrigger('Image', 'image', Icons.image_outlined),
                  _emptyPageBlockTrigger('Link', 'subpage_link', Icons.link),
                  _emptyPageBlockTrigger('Code Block', 'code', Icons.code, initialContent: 'javascript\nconsole.log("Hello from Cero Code!");\n'),
                  _emptyPageBlockTrigger('HTML Site', 'sites', Icons.web, initialContent: '{"name": "Interactive Site Widget", "description": "Sandboxed HTML preview widget", "html": "<h1>Welcome directly to Sandboxed Environment!</h1>"}'),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        ReorderableListView(
          scrollController: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          onReorder: _onReorder,
          children: [
            for (final entry in widget.cards.asMap().entries)
              Column(
                key: ValueKey(entry.value.id),
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildInsertButton(entry.key),
                  _buildCard(entry.value, entry.key),
                  if (entry.key == widget.cards.length - 1) _buildInsertButton(entry.key + 1),
                ],
              ),
          ],
        ),
        if (_showScrollToBottom)
          Positioned(
            right: 20,
            bottom: 20,
            child: FloatingActionButton.small(
              heroTag: null,
              backgroundColor: const Color(0xFF818CF8),
              foregroundColor: Colors.white,
              onPressed: () {
                widget.scrollController?.animateTo(
                  widget.scrollController!.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              },
              child: const Icon(Icons.arrow_downward, size: 20),
            ),
          ),
      ],
    );
  }

  Widget _emptyPageBlockTrigger(String label, String type, IconData icon, {String initialContent = ''}) {
    return ElevatedButton.icon(
      onPressed: () => widget.onCardAdded(widget.selectedPage.id, type, initialContent),
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF818CF8).withValues(alpha: 0.12),
        foregroundColor: const Color(0xFF818CF8),
        elevation: 0,
      ),
    );
  }

  Widget _buildInsertButton(int index) {
    return GestureDetector(
      onTap: () => _showAddCardMenu(index),
      child: Container(
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            const Expanded(child: Divider(height: 1, color: Color(0xFF2C2C2C))),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: const Color(0xFF222222),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.add, size: 11, color: Color(0xFF64748B)),
            ),
            const Expanded(child: Divider(height: 1, color: Color(0xFF2C2C2C))),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(models.Card card, int index) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF18181A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF262629)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCardContent(card),
          _buildSleekInteractiveCommentStrip(card),
        ],
      ),
    );
  }

  Widget _buildCardContent(models.Card card) {
    final index = _cardIndex(card);
    switch (card.type) {
      case 'markdown':
        return MarkdownCard(
          card: card,
          onContentChanged: (content) => widget.onCardUpdated(card.id, content),
          onDelete: () => widget.onCardDeleted(card.id),
          onMoveUp: index > 0 ? () => _moveCard(index, -1) : null,
          onMoveDown: index < widget.cards.length - 1 ? () => _moveCard(index, 1) : null,
          cardIndex: index,
        );
      case 'image':
        return ImageCard(
          card: card,
          onContentChanged: (content) => widget.onCardUpdated(card.id, content),
          onDelete: () => widget.onCardDeleted(card.id),
          onMoveUp: index > 0 ? () => _moveCard(index, -1) : null,
          onMoveDown: index < widget.cards.length - 1 ? () => _moveCard(index, 1) : null,
          cardIndex: index,
          dbService: widget.dbService,
        );
      case 'subpage_link':
        return SubpageLinkCard(
          card: card,
          allPages: widget.allPages,
          currentPage: widget.selectedPage,
          onNavigate: widget.onNavigateToPage,
          onContentChanged: (content) => widget.onCardUpdated(card.id, content),
          onCreateNewPage: widget.onCreateNewPage,
          onDelete: () => widget.onCardDeleted(card.id),
          onMoveUp: index > 0 ? () => _moveCard(index, -1) : null,
          onMoveDown: index < widget.cards.length - 1 ? () => _moveCard(index, 1) : null,
          cardIndex: index,
          dbService: widget.dbService,
        );
      case 'code':
        return CodeCard(
          card: card,
          onContentChanged: (content) => widget.onCardUpdated(card.id, content),
          onDelete: () => widget.onCardDeleted(card.id),
          onMoveUp: index > 0 ? () => _moveCard(index, -1) : null,
          onMoveDown: index < widget.cards.length - 1 ? () => _moveCard(index, 1) : null,
          cardIndex: index,
        );
      case 'sites':
        return SitesCard(
          card: card,
          onContentChanged: (content) => widget.onCardUpdated(card.id, content),
          onDelete: () => widget.onCardDeleted(card.id),
          onMoveUp: index > 0 ? () => _moveCard(index, -1) : null,
          onMoveDown: index < widget.cards.length - 1 ? () => _moveCard(index, 1) : null,
          cardIndex: index,
        );
      default:
        return MarkdownCard(
          card: card,
          onContentChanged: (content) => widget.onCardUpdated(card.id, content),
          onDelete: () => widget.onCardDeleted(card.id),
          onMoveUp: index > 0 ? () => _moveCard(index, -1) : null,
          onMoveDown: index < widget.cards.length - 1 ? () => _moveCard(index, 1) : null,
          cardIndex: index,
        );
    }
  }

  Widget _buildSleekInteractiveCommentStrip(models.Card card) {
    final comments = card.commentsList;
    final hasComments = comments.isNotEmpty;

    return InkWell(
      onTap: () => _openCommentsBottomSheet(card),
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          color: Color(0xFF141416),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
          border: Border(top: BorderSide(color: Color(0xFF232326))),
        ),
        child: Row(
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 13,
              color: hasComments ? const Color(0xFF818CF8) : const Color(0xFF52525B),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                hasComments
                    ? '${comments.length} Comment${comments.length > 1 ? 's' : ''}'
                    : 'Add a comment...',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: hasComments ? FontWeight.w600 : FontWeight.w500,
                  color: hasComments ? const Color(0xFF818CF8) : const Color(0xFF71717A),
                ),
              ),
            ),
            if (hasComments) ...[
              Expanded(
                flex: 2,
                child: Text(
                  comments.first.text,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF52525B),
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
              const SizedBox(width: 4),
            ],
            const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Color(0xFF3F3F46)),
          ],
        ),
      ),
    );
  }

  void _showAddCardMenu(int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF202020),
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Add Block', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              _addBlockOption(ctx, 'Markdown', 'Write formatted text', Icons.text_fields, 'markdown', ''),
              _addBlockOption(ctx, 'Image', 'Embed visual images', Icons.image_outlined, 'image', ''),
              _addBlockOption(ctx, 'Subpage Link', 'Create nested references', Icons.link, 'subpage_link', ''),
              _addBlockOption(ctx, 'Code Block', 'Syntax-highlighted code', Icons.code, 'code', 'javascript\nconsole.log("Hello from Cero Code!");\n'),
              _addBlockOption(ctx, 'HTML Site', 'Render custom local template widgets', Icons.web, 'sites', '{"name": "Site Widget", "html": "<h1>Hello Cero Sandbox</h1>"}'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addBlockOption(BuildContext ctx, String title, String subtitle, IconData icon, String type, String initialContent) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF818CF8)),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 11)),
      onTap: () {
        Navigator.pop(ctx);
        widget.onCardAdded(widget.selectedPage.id, type, initialContent);
      },
    );
  }
}

// --- Dynamic Real-Time Bottom Sheet Portal ---
class _CommentsBottomSheetContent extends StatefulWidget {
  final models.Card initialCard;
  final ServerService serverService;
  final Future<void> Function(String cardId, String content) onCardUpdated;

  const _CommentsBottomSheetContent({
    required this.initialCard,
    required this.serverService,
    required this.onCardUpdated,
  });

  @override
  State<_CommentsBottomSheetContent> createState() => _CommentsBottomSheetContentState();
}

class _CommentsBottomSheetContentState extends State<_CommentsBottomSheetContent> {
  final TextEditingController _textController = TextEditingController();
  final Set<String> _submittingIds = {};
  String? _localEditingCommentId;
  late models.Card _card;

  @override
  void initState() {
    super.initState();
    _card = widget.initialCard;
    widget.serverService.addListener(_onServerDataChanged);
  }

  @override
  void dispose() {
    widget.serverService.removeListener(_onServerDataChanged);
    _textController.dispose();
    super.dispose();
  }

  void _onServerDataChanged() async {
    final freshCards = await widget.serverService.dbService.getCards(_card.pageId);
    final updatedCard = freshCards.firstWhere((c) => c.id == _card.id, orElse: () => _card);
    if (mounted) {
      setState(() {
        _card = updatedCard;
      });
    }
  }

  Future<void> _saveComment() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    if (_submittingIds.contains(_card.id)) return;
    _submittingIds.add(_card.id);

    final comments = _card.commentsList;

    if (_localEditingCommentId == null && comments.isNotEmpty) {
      final lastComment = comments.first;
      if (lastComment.text == text && DateTime.now().difference(lastComment.createdAt).inSeconds < 3) {
        _submittingIds.remove(_card.id);
        _textController.clear();
        return;
      }
    }

    final List<models.CommentItem> updatedComments = List.from(comments);
    final String? commentToEditId = _localEditingCommentId;

    if (commentToEditId != null) {
      final idx = updatedComments.indexWhere((c) => c.id == commentToEditId);
      if (idx != -1) {
        updatedComments[idx] = updatedComments[idx].copyWith(text: text);
      }
    } else {
      updatedComments.insert(0, models.CommentItem(
        id: _generateId(),
        text: text,
        createdAt: DateTime.now(),
      ));
    }

    _textController.clear();
    setState(() {
      _localEditingCommentId = null;
    });

    try {
      final updatedCard = _card.copyWith(
        comment: models.Card.commentsToJson(updatedComments),
        updatedAt: DateTime.now(),
        revision: _card.revision + 1,
      );
      await widget.serverService.dbService.updateCard(updatedCard);
      await widget.onCardUpdated(_card.id, _card.content);
    } finally {
      _submittingIds.remove(_card.id);
    }
  }

  void _deleteComment(String commentId) async {
    final List<models.CommentItem> updatedComments = List.from(_card.commentsList);
    updatedComments.removeWhere((c) => c.id == commentId);

    final updatedCard = _card.copyWith(
      comment: models.Card.commentsToJson(updatedComments),
      updatedAt: DateTime.now(),
      revision: _card.revision + 1,
    );
    await widget.serverService.dbService.updateCard(updatedCard);
    await widget.onCardUpdated(_card.id, _card.content);
  }

  @override
  Widget build(BuildContext context) {
    final comments = _card.commentsList;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.55,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF2E2E33),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFF818CF8)),
                    const SizedBox(width: 8),
                    Text(
                      'Comments (${comments.length})',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: Color(0xFF71717A)),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const Divider(color: Color(0xFF242427), height: 24, thickness: 1),
            Expanded(
              child: comments.isEmpty
                  ? const Center(
                      child: Text(
                        'No comments yet.\nWrite below to start a discussion.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF52525B), fontSize: 12, height: 1.5),
                      ),
                    )
                  : ListView.builder(
                      itemCount: comments.length,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemBuilder: (context, index) {
                        final comment = comments[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF2A2A2F)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDate(comment.createdAt),
                                    style: const TextStyle(color: Color(0xFF71717A), fontSize: 10),
                                  ),
                                  Row(
                                    children: [
                                      GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _localEditingCommentId = comment.id;
                                            _textController.text = comment.text;
                                          });
                                        },
                                        child: const Text('Edit', style: TextStyle(color: Color(0xFF818CF8), fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 12),
                                      GestureDetector(
                                        onTap: () => _deleteComment(comment.id),
                                        child: const Text('Delete', style: TextStyle(color: Color(0xFFF87171), fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  )
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                comment.text,
                                style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 13, height: 1.4),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    style: const TextStyle(fontSize: 13, color: Colors.white),
                    decoration: InputDecoration(
                      hintText: _localEditingCommentId != null ? 'Edit selected comment...' : 'Write comment...',
                      hintStyle: const TextStyle(color: Color(0xFF52525B), fontSize: 13),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      filled: true,
                      fillColor: const Color(0xFF0F0F11),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF2A2A2F)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF2A2A2F)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF818CF8), width: 1.5),
                      ),
                    ),
                    onSubmitted: (_) => _saveComment(),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  icon: const Icon(Icons.send_rounded, color: Color(0xFF818CF8), size: 22),
                  onPressed: _saveComment,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
