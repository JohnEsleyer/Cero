import 'dart:math';
import 'package:flutter/material.dart';
import '../models/page_model.dart';
import '../models/card_model.dart' as models;
import '../services/database_service.dart';
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
    this.onCreateNewPage,
    this.scrollController,
    this.dbService,
  });

  @override
  State<CardColumn> createState() => _CardColumnState();
}

class _CardColumnState extends State<CardColumn> {
  bool _showScrollToBottom = false;
  final Map<String, bool> _commentExpanded = {};
  final Map<String, String?> _editingCommentId = {};
  final Map<String, TextEditingController> _commentControllers = {};

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_scrollListener);
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_scrollListener);
    for (final c in _commentControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggleComment(models.Card card) {
    setState(() {
      final expanded = _commentExpanded[card.id] ?? false;
      _commentExpanded[card.id] = !expanded;
      if (!expanded) {
        _editingCommentId[card.id] = null;
        _commentControllers.putIfAbsent(card.id, () => TextEditingController());
        _commentControllers[card.id]!.clear();
      }
    });
  }

  void _startNewComment(models.Card card) {
    setState(() {
      _editingCommentId[card.id] = null;
      _commentControllers.putIfAbsent(card.id, () => TextEditingController());
      _commentControllers[card.id]!.clear();
    });
  }

  void _startEditComment(models.Card card, String commentId, String text) {
    setState(() {
      _editingCommentId[card.id] = commentId;
      _commentControllers.putIfAbsent(card.id, () => TextEditingController());
      _commentControllers[card.id]!.text = text;
    });
  }

  Future<void> _saveComment(models.Card card) async {
    final controller = _commentControllers[card.id];
    final text = controller?.text.trim() ?? '';
    if (text.isEmpty) {
      setState(() => _editingCommentId[card.id] = null);
      return;
    }
    final comments = card.commentsList;
    final editingId = _editingCommentId[card.id];
    if (editingId != null) {
      final idx = comments.indexWhere((c) => c.id == editingId);
      if (idx != -1) {
        comments[idx] = comments[idx].copyWith(text: text);
      }
    } else {
      comments.insert(0, models.CommentItem(
        id: _generateId(),
        text: text,
        createdAt: DateTime.now(),
      ));
    }
    setState(() => _editingCommentId[card.id] = null);
    if (widget.dbService != null) {
      final updated = card.copyWith(
        comment: models.Card.commentsToJson(comments),
        updatedAt: DateTime.now(),
        revision: card.revision + 1,
      );
      await widget.dbService!.updateCard(updated);
      widget.onCardUpdated(card.id, card.content);
    }
  }

  void _deleteComment(models.Card card, String commentId) {
    final comments = card.commentsList;
    comments.removeWhere((c) => c.id == commentId);
    if (widget.dbService != null) {
      final updated = card.copyWith(
        comment: models.Card.commentsToJson(comments),
        updatedAt: DateTime.now(),
        revision: card.revision + 1,
      );
      widget.dbService!.updateCard(updated);
      widget.onCardUpdated(card.id, card.content);
      setState(() {
        _editingCommentId[card.id] = null;
        if (comments.isEmpty) _commentExpanded[card.id] = false;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.note_alt_outlined,
                size: 64,
                color: Color(0xFF4A4A4A),
              ),
              const SizedBox(height: 16),
              const Text(
                'This page is empty',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add blocks to start writing and organizing your thoughts.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () => widget.onCardAdded(widget.selectedPage.id, 'markdown', ''),
                    icon: const Icon(Icons.text_fields, size: 16),
                    label: const Text('Markdown'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF818CF8).withOpacity(0.15),
                      foregroundColor: const Color(0xFF818CF8),
                      elevation: 0,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => widget.onCardAdded(widget.selectedPage.id, 'image', ''),
                    icon: const Icon(Icons.image_outlined, size: 16),
                    label: const Text('Image'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF818CF8).withOpacity(0.15),
                      foregroundColor: const Color(0xFF818CF8),
                      elevation: 0,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => widget.onCardAdded(widget.selectedPage.id, 'subpage_link', ''),
                    icon: const Icon(Icons.link, size: 16),
                    label: const Text('Link'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF818CF8).withOpacity(0.15),
                      foregroundColor: const Color(0xFF818CF8),
                      elevation: 0,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => widget.onCardAdded(
                      widget.selectedPage.id,
                      'code',
                      'javascript\nconsole.log("Hello from Cero Code Block!");\n',
                    ),
                    icon: const Icon(Icons.code, size: 16),
                    label: const Text('Code Block'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF818CF8).withOpacity(0.15),
                      foregroundColor: const Color(0xFF818CF8),
                      elevation: 0,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: () => widget.onCardAdded(
                      widget.selectedPage.id,
                      'sites',
                      '{"name": "Interactive Site Widget", "description": "Sandboxed HTML preview widget", "html": "<h1>Welcome directly to Sandboxed Environment!</h1>\\n<p>Change this code inside the editor tab to render customized HTML components.</p>"}',
                    ),
                    icon: const Icon(Icons.web, size: 16),
                    label: const Text('HTML Site'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF818CF8).withOpacity(0.15),
                      foregroundColor: const Color(0xFF818CF8),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: ReorderableListView(
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

  Widget _buildInsertButton(int index) {
    return GestureDetector(
      onTap: () => _showAddCardMenu(index),
      child: Container(
        height: 24,
        margin: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            const Expanded(child: Divider(height: 1, color: Color(0xFF2E2E2E))),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: const Color(0xFF2E2E2E),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.add, size: 12, color: Color(0xFF64748B)),
            ),
            const Expanded(child: Divider(height: 1, color: Color(0xFF2E2E2E))),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(models.Card card, int index) {
    return LongPressDraggable<int>(
      data: index,
      onDragStarted: () {},
      onDragEnd: (_) {},
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.8,
          child: SizedBox(
            width: MediaQuery.of(context).size.width - 40,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCardContent(card),
                if (card.comment.isNotEmpty) _buildCommentBubble(card),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCardContent(card),
            if (card.comment.isNotEmpty) _buildCommentBubble(card),
          ],
        ),
      ),
      child: DragTarget<int>(
        onWillAcceptWithDetails: (details) => details.data != index,
        onAcceptWithDetails: (details) => _onReorder(details.data, index),
        builder: (context, candidateData, rejectedData) {
          final isHovering = candidateData.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              border: isHovering
                  ? Border.all(color: const Color(0xFF818CF8), width: 2)
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildCardContent(card),
                _buildInteractiveCommentSection(card),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCommentBubble(models.Card card) {
    final comments = card.commentsList;
    if (comments.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(left: 12, right: 12, bottom: 8, top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF131313),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF2C2C2C)),
      ),
      child: Row(
        children: [
          const Icon(Icons.chat_bubble_outline, size: 12, color: Color(0xFF818CF8)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${comments.length} comment${comments.length > 1 ? 's' : ''}',
              style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractiveCommentSection(models.Card card) {
    final expanded = _commentExpanded[card.id] ?? false;
    final comments = card.commentsList;
    final hasComment = comments.isNotEmpty;
    final editingId = _editingCommentId[card.id];
    final isAdding = expanded && editingId == null;
    final controller = _commentControllers.putIfAbsent(
      card.id,
      () => TextEditingController(),
    );

    return Container(
      margin: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Toggle button (always visible)
          GestureDetector(
            onTap: () => _toggleComment(card),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(
                  color: hasComment
                      ? const Color(0xFF818CF8).withOpacity(0.15)
                      : const Color(0xFF2E2E2E),
                ),
                borderRadius: BorderRadius.circular(6),
                color: hasComment
                    ? const Color(0xFF818CF8).withOpacity(0.03)
                    : Colors.transparent,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 11,
                    color: hasComment ? const Color(0xFF818CF8) : const Color(0xFF52525B),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    hasComment ? '${comments.length} Comment${comments.length > 1 ? 's' : ''}' : 'Add comment',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: hasComment ? const Color(0xFF818CF8) : const Color(0xFF52525B),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 10,
                    color: hasComment ? const Color(0xFF818CF8) : const Color(0xFF52525B),
                  ),
                ],
              ),
            ),
          ),

          // Dropdown panel
          if (expanded)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF131313),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF2C2C2C)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Existing comments list
                  ...comments.map((c) => _buildCommentRow(card, c)),
                  if (comments.isNotEmpty && !isAdding) const SizedBox(height: 6),
                  // Add or edit input
                  if (isAdding)
                    _buildCommentInput(card, controller)
                  else if (!isAdding && editingId == null)
                    GestureDetector(
                      onTap: () => _startNewComment(card),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Icon(Icons.add, size: 10, color: Color(0xFF818CF8)),
                            SizedBox(width: 4),
                            Text(
                              'Add comment',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF818CF8)),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCommentRow(models.Card card, models.CommentItem c) {
    final editingId = _editingCommentId[card.id];
    if (editingId == c.id) {
      return _buildCommentInput(card, _commentControllers[card.id]!);
    }
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.chat_bubble_outline, size: 11, color: Color(0xFF818CF8)),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: GestureDetector(
              onDoubleTap: () => _startEditComment(card, c.id, c.text),
              child: Text(
                c.text,
                style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1), height: 1.3),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _startEditComment(card, c.id, c.text),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('edit', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Color(0xFF52525B))),
            ),
          ),
          GestureDetector(
            onTap: () => _deleteComment(card, c.id),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('×', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF52525B))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentInput(models.Card card, TextEditingController ctrl) {
    return Row(
      children: [
        const Icon(Icons.chat_bubble_outline, size: 11, color: Color(0xFF818CF8)),
        const SizedBox(width: 6),
        Expanded(
          child: TextField(
            controller: ctrl,
            style: const TextStyle(fontSize: 11, color: Color(0xFFCBD5E1)),
            decoration: const InputDecoration(
              hintText: 'Write a comment...',
              hintStyle: TextStyle(fontSize: 11, color: Color(0xFF52525B)),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: (_) => _saveComment(card),
            onChanged: (_) => setState(() {}),
            autofocus: true,
          ),
        ),
      ],
    );
  }

  Widget _buildCardContent(models.Card card) {
    final index = _cardIndex(card) + 1;
    switch (card.type) {
      case 'image':
        return ImageCard(
          card: card,
          cardIndex: index,
          dbService: widget.dbService,
          onContentChanged: (content) => widget.onCardUpdated(card.id, content),
          onDelete: () => widget.onCardDeleted(card.id),
          onMoveUp: _cardIndex(card) > 0 ? () => _moveCard(_cardIndex(card), -1) : null,
          onMoveDown: _cardIndex(card) < widget.cards.length - 1 ? () => _moveCard(_cardIndex(card), 1) : null,
        );
      case 'subpage_link':
        return SubpageLinkCard(
          card: card,
          allPages: widget.allPages,
          currentPage: widget.selectedPage,
          cardIndex: index,
          dbService: widget.dbService,
          onNavigate: widget.onNavigateToPage,
          onContentChanged: (content) => widget.onCardUpdated(card.id, content),
          onCreateNewPage: widget.onCreateNewPage,
          onDelete: () => widget.onCardDeleted(card.id),
          onMoveUp: _cardIndex(card) > 0 ? () => _moveCard(_cardIndex(card), -1) : null,
          onMoveDown: _cardIndex(card) < widget.cards.length - 1 ? () => _moveCard(_cardIndex(card), 1) : null,
        );
      case 'code':
        return CodeCard(
          card: card,
          cardIndex: index,
          onContentChanged: (content) => widget.onCardUpdated(card.id, content),
          onDelete: () => widget.onCardDeleted(card.id),
          onMoveUp: _cardIndex(card) > 0 ? () => _moveCard(_cardIndex(card), -1) : null,
          onMoveDown: _cardIndex(card) < widget.cards.length - 1 ? () => _moveCard(_cardIndex(card), 1) : null,
        );
      case 'sites':
        return SitesCard(
          card: card,
          cardIndex: index,
          onContentChanged: (content) => widget.onCardUpdated(card.id, content),
          onDelete: () => widget.onCardDeleted(card.id),
          onMoveUp: _cardIndex(card) > 0 ? () => _moveCard(_cardIndex(card), -1) : null,
          onMoveDown: _cardIndex(card) < widget.cards.length - 1 ? () => _moveCard(_cardIndex(card), 1) : null,
        );
      default:
        return MarkdownCard(
          card: card,
          cardIndex: index,
          onContentChanged: (content) => widget.onCardUpdated(card.id, content),
          onDelete: () => widget.onCardDeleted(card.id),
          onMoveUp: _cardIndex(card) > 0 ? () => _moveCard(_cardIndex(card), -1) : null,
          onMoveDown: _cardIndex(card) < widget.cards.length - 1 ? () => _moveCard(_cardIndex(card), 1) : null,
        );
    }
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
                child: Text('Add card', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              ListTile(
                leading: const Icon(Icons.text_fields, color: Color(0xFF818CF8)),
                title: const Text('Markdown', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Write formatted text', style: TextStyle(color: Colors.grey, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onCardAdded(widget.selectedPage.id, 'markdown', '');
                },
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined, color: Color(0xFF818CF8)),
                title: const Text('Image', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Embed an image', style: TextStyle(color: Colors.grey, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onCardAdded(widget.selectedPage.id, 'image', '');
                },
              ),
              ListTile(
                leading: const Icon(Icons.link, color: Color(0xFF818CF8)),
                title: const Text('Subpage Link', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Link to another page', style: TextStyle(color: Colors.grey, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onCardAdded(widget.selectedPage.id, 'subpage_link', '');
                },
              ),
              ListTile(
                leading: const Icon(Icons.code, color: Color(0xFF818CF8)),
                title: const Text('Code Block', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Write syntax-highlighted code', style: TextStyle(color: Colors.grey, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onCardAdded(
                    widget.selectedPage.id,
                    'code',
                    'javascript\nconsole.log("Hello from Cero Code Block!");\n',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.web, color: Color(0xFF818CF8)),
                title: const Text('HTML Site', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Render customized sandboxed HTML widget', style: TextStyle(color: Colors.grey, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onCardAdded(
                    widget.selectedPage.id,
                    'sites',
                    '{"name": "Interactive Site Widget", "description": "Sandboxed HTML preview widget", "html": "<h1>Welcome directly to Sandboxed Environment!</h1>\\n<p>Change this code inside the editor tab to render customized HTML components.</p>"}',
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}