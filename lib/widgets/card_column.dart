import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/page_model.dart';
import '../models/card_model.dart' as models;
import '../services/database_service.dart';
import '../services/server_service.dart';
import '../screens/comments_screen.dart';
import 'markdown_card.dart';
import 'image_card.dart';
import 'subpage_link_card.dart';
import 'code_card.dart'; 
import 'sites_card.dart';
import 'page_icon.dart';

class CardColorPreset {
  final Color bg;
  final Color text;
  final Color border;
  final Color textMuted;
  final String label;

  const CardColorPreset({
    required this.bg,
    required this.text,
    required this.border,
    required this.textMuted,
    required this.label,
  });
}

const Map<String, CardColorPreset> colorPresets = {
  'default': CardColorPreset(
    bg: Color(0xFF1E1E1E),
    text: Color(0xFFCBD5E1),
    border: Color(0xFF2E2E2E),
    textMuted: Color(0xFF71717A),
    label: 'Default',
  ),
  'red': CardColorPreset(
    bg: Color(0xFFFEE2E2),
    text: Color(0xFF991B1B),
    border: Color(0xFFFCA5A5),
    textMuted: Color(0xFFB91C1C),
    label: 'Red',
  ),
  'orange': CardColorPreset(
    bg: Color(0xFFFFEDD5),
    text: Color(0xFF9A3412),
    border: Color(0xFFFDBA74),
    textMuted: Color(0xFFC2410C),
    label: 'Orange',
  ),
  'yellow': CardColorPreset(
    bg: Color(0xFFFEF9C3),
    text: Color(0xFF854D0E),
    border: Color(0xFFFDE047),
    textMuted: Color(0xFFA16207),
    label: 'Yellow',
  ),
  'green': CardColorPreset(
    bg: Color(0xFFD1FAE5),
    text: Color(0xFF065F46),
    border: Color(0xFF6EE7B7),
    textMuted: Color(0xFF047857),
    label: 'Green',
  ),
  'blue': CardColorPreset(
    bg: Color(0xFFDBEAFE),
    text: Color(0xFF1E40AF),
    border: Color(0xFF93C5FD),
    textMuted: Color(0xFF1D4ED8),
    label: 'Blue',
  ),
  'purple': CardColorPreset(
    bg: Color(0xFFF3E8FF),
    text: Color(0xFF6B21A8),
    border: Color(0xFFC084FC),
    textMuted: Color(0xFF7E22CE),
    label: 'Purple',
  ),
};

class CardMetadata {
  final String color;
  final List<String> comments;

  CardMetadata({this.color = 'default', this.comments = const []});

  factory CardMetadata.fromJsonString(String? jsonStr) {
    if (jsonStr == null || jsonStr.isEmpty) {
      return CardMetadata();
    }
    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      final color = data['color'] as String? ?? 'default';
      final commentsList = data['comments'] as List<dynamic>? ?? [];
      final comments = commentsList.map((e) => e.toString()).toList();
      return CardMetadata(color: color, comments: comments);
    } catch (_) {
      if (colorPresets.containsKey(jsonStr)) {
        return CardMetadata(color: jsonStr);
      }
      return CardMetadata(color: 'default', comments: [jsonStr]);
    }
  }

  String toJsonString() {
    return jsonEncode({
      'color': color,
      'comments': comments,
    });
  }
}

class CardColumn extends StatefulWidget {
  final List<models.Card> cards;
  final List<DbPage> allPages;
  final DbPage selectedPage;
  final ValueChanged<DbPage> onNavigateToPage;
  final Future<void> Function(String cardId, String content) onCardUpdated;
  final Future<void> Function(String pageId, String type, String content, {int? insertAt}) onCardAdded;
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
    required this.onCardDeleted,
    required this.onCardsReordered,
    required this.serverService,
    this.onCreateNewPage,
    this.scrollController,
    this.dbService,
    required this.onCardAdded,
  });

  @override
  State<CardColumn> createState() => _CardColumnState();
}

class _CardColumnState extends State<CardColumn> {
  bool _showScrollToBottom = false;
  bool _isPaginatedView = false;
  int _currentBlockIndex = 0;
  final TextEditingController _blockNumberController = TextEditingController();
  int? _pendingBlockIndex;

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_scrollListener);
    _blockNumberController.text = (_currentBlockIndex + 1).toString();
  }

  @override
  void didUpdateWidget(CardColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPage.id != widget.selectedPage.id) {
      _currentBlockIndex = 0;
      _blockNumberController.text = '1';
      _pendingBlockIndex = null;
    }
    if (_pendingBlockIndex != null) {
      if (_pendingBlockIndex! >= 0 && _pendingBlockIndex! < widget.cards.length) {
        _currentBlockIndex = _pendingBlockIndex!;
        _blockNumberController.text = (_currentBlockIndex + 1).toString();
        _pendingBlockIndex = null;
      }
    }
    if (_currentBlockIndex >= widget.cards.length) {
      _currentBlockIndex = widget.cards.isEmpty ? 0 : widget.cards.length - 1;
      _blockNumberController.text = (_currentBlockIndex + 1).toString();
    }
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_scrollListener);
    _blockNumberController.dispose();
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

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        border: Border(top: BorderSide(color: Color(0xFF2C2C2C))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () {
                setState(() {
                  _isPaginatedView = !_isPaginatedView;
                  if (_isPaginatedView) {
                    if (_currentBlockIndex >= widget.cards.length) {
                      _currentBlockIndex = widget.cards.isEmpty ? 0 : widget.cards.length - 1;
                    }
                    _blockNumberController.text = (_currentBlockIndex + 1).toString();
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _isPaginatedView 
                      ? const Color(0xFF818CF8).withOpacity(0.12) 
                      : Colors.white.withValues(alpha: 0.02),
                  border: Border.all(
                    color: _isPaginatedView 
                        ? const Color(0xFF818CF8).withOpacity(0.35) 
                        : Colors.white.withValues(alpha: 0.05),
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isPaginatedView ? Icons.crop_din_outlined : Icons.unfold_more_outlined,
                      size: 14,
                      color: _isPaginatedView ? const Color(0xFF818CF8) : const Color(0xFFCBD5E1),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isPaginatedView ? 'Block View' : 'Scroll View',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _isPaginatedView ? const Color(0xFF818CF8) : const Color(0xFFCBD5E1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_isPaginatedView && widget.cards.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.first_page, size: 16, color: Color(0xFF818CF8)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _currentBlockIndex > 0 ? () {
                        setState(() {
                          _currentBlockIndex = 0;
                          _blockNumberController.text = '1';
                        });
                      } : null,
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 16, color: Color(0xFF818CF8)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _currentBlockIndex > 0 ? () {
                        setState(() {
                          _currentBlockIndex--;
                          _blockNumberController.text = (_currentBlockIndex + 1).toString();
                        });
                      } : null,
                    ),
                    const SizedBox(width: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          child: TextField(
                            controller: _blockNumberController,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              border: InputBorder.none,
                            ),
                            onSubmitted: (val) {
                              final parsed = int.tryParse(val);
                              if (parsed != null && parsed >= 1 && parsed <= widget.cards.length) {
                                setState(() {
                                  _currentBlockIndex = parsed - 1;
                                });
                              } else {
                                _blockNumberController.text = (_currentBlockIndex + 1).toString();
                              }
                            },
                          ),
                        ),
                        const Text('/', style: TextStyle(fontSize: 10, color: Color(0xFF3F3F46))),
                        const SizedBox(width: 2),
                        Text(
                          '${widget.cards.length}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF71717A), fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 16, color: Color(0xFF818CF8)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _currentBlockIndex < widget.cards.length - 1 ? () {
                        setState(() {
                          _currentBlockIndex++;
                          _blockNumberController.text = (_currentBlockIndex + 1).toString();
                        });
                      } : null,
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.last_page, size: 16, color: Color(0xFF818CF8)),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: _currentBlockIndex < widget.cards.length - 1 ? () {
                        setState(() {
                          _currentBlockIndex = widget.cards.length - 1;
                          _blockNumberController.text = widget.cards.length.toString();
                        });
                      } : null,
                    ),
                  ],
                ),
              )
            else if (!_isPaginatedView)
              const Text(
                'CONTINUOUS',
                style: TextStyle(fontSize: 9, color: Color(0xFF52525B), fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
          ],
        ),
      ),
    );
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
                'Add blocks to start writing and organizing.',
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
                  _emptyPageBlockTrigger('Code Block', 'code', Icons.code, initialContent: 'javascript\nconsole.log("Hello!");\n'),
                  _emptyPageBlockTrigger('HTML Site', 'sites', Icons.web, initialContent: '{"name": "Site Widget", "html": "<h1>Hello Sandbox</h1>"}'),
                  _emptyPageBlockTrigger('Section Divider', 'section', Icons.title_outlined, initialContent: 'New Section'),
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
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _isPaginatedView
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                      child: Column(
                        children: [
                          _buildInsertButton(_currentBlockIndex),
                          _buildCard(widget.cards[_currentBlockIndex], _currentBlockIndex),
                          _buildInsertButton(_currentBlockIndex + 1),
                        ],
                      ),
                    )
                  : ReorderableListView(
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
            _buildBottomBar(),
          ],
        ),
        if (_showScrollToBottom && !_isPaginatedView)
          Positioned(
            right: 20,
            bottom: 60,
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
      onPressed: () {
        if (_isPaginatedView) {
          _pendingBlockIndex = 0;
        }
        widget.onCardAdded(widget.selectedPage.id, type, initialContent, insertAt: 0);
      },
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

  Widget _buildHeaderActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    double size = 12.0,
    String? tooltip,
  }) {
    return GestureDetector(
      onTap: onPressed,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        child: Icon(icon, size: size, color: color),
      ),
    );
  }

  Widget _buildCard(models.Card card, int index) {
    if (card.type == 'section') {
      return _buildSectionDividerCard(card, index);
    }

    final meta = CardMetadata.fromJsonString(card.comment);
    final activePreset = colorPresets[meta.color] ?? colorPresets['default']!;

    return GestureDetector(
      onLongPress: () => _showBlockOptionsMenu(card, index),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: activePreset.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: activePreset.border),
        ),
        child: Theme(
          data: ThemeData(
            textTheme: TextTheme(
              bodyMedium: TextStyle(color: activePreset.text),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: activePreset.textMuted.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '#${index + 1}',
                        style: TextStyle(fontSize: 9, color: activePreset.text, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        card.type.toUpperCase(),
                        style: TextStyle(fontSize: 8.5, color: activePreset.textMuted, fontWeight: FontWeight.w800, letterSpacing: 0.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (card.type == 'markdown') ...[
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CommentsScreen(
                                card: card,
                                cardIndex: index + 1,
                                serverService: widget.serverService,
                                onCommentsUpdated: () {
                                  widget.onCardUpdated(card.id, card.content);
                                },
                              ),
                            ),
                          );
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Icon(
                                Icons.comment_outlined,
                                size: 13,
                                color: meta.comments.isNotEmpty
                                    ? const Color(0xFF818CF8)
                                    : activePreset.textMuted,
                              ),
                              if (meta.comments.isNotEmpty)
                                Positioned(
                                  top: -6,
                                  right: -6,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF818CF8),
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 11,
                                      minHeight: 11,
                                    ),
                                    child: Text(
                                      '${meta.comments.length}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 7,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    SizedBox(width: 16, child: _buildColorPicker(card, meta, activePreset)),
                    const SizedBox(width: 8),
                    if (index > 0)
                      _buildHeaderActionButton(
                        icon: Icons.arrow_upward,
                        color: activePreset.textMuted,
                        size: 15,
                        onPressed: () => _moveCard(index, -1),
                      ),
                    if (index > 0 && index < widget.cards.length - 1)
                      const SizedBox(width: 4),
                    if (index < widget.cards.length - 1)
                      _buildHeaderActionButton(
                        icon: Icons.arrow_downward,
                        color: activePreset.textMuted,
                        size: 15,
                        onPressed: () => _moveCard(index, 1),
                      ),
                    const SizedBox(width: 16),
                    _buildHeaderActionButton(
                      icon: Icons.delete_outline,
                      color: Colors.redAccent,
                      size: 14,
                      onPressed: () => widget.onCardDeleted(card.id),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFF2C2C2C)),
              _buildCardContent(card),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildColorPicker(models.Card card, CardMetadata meta, CardColorPreset activePreset) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.circle, size: 10, color: activePreset.textMuted),
      tooltip: 'Change Block Color',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onSelected: (colorKey) async {
        final newMeta = CardMetadata(color: colorKey, comments: meta.comments);
        await widget.serverService.updateCard(id: card.id, comment: newMeta.toJsonString());
        await widget.onCardUpdated(card.id, card.content);
      },
      itemBuilder: (context) => colorPresets.entries.map((entry) {
        return PopupMenuItem<String>(
          value: entry.key,
          child: Row(
            children: [
              Icon(Icons.circle, size: 12, color: entry.value.textMuted),
              const SizedBox(width: 8),
              Text(entry.value.label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionDividerCard(models.Card card, int index) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PageIcon(emoji: 'heading', size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onDoubleTap: () async {
                    final controller = TextEditingController(text: card.content);
                    final newTitle = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF202020),
                        title: const Text('Edit Section Header'),
                        content: TextField(
                          controller: controller,
                          autofocus: true,
                          style: const TextStyle(color: Colors.white),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    );
                    if (newTitle != null && newTitle.isNotEmpty) {
                      widget.onCardUpdated(card.id, newTitle);
                    }
                  },
                  child: Text(
                    card.content.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
              ),
              if (index > 0)
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up, size: 14, color: Color(0xFF71717A)),
                  onPressed: () => _moveCard(index, -1),
                ),
              if (index < widget.cards.length - 1)
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down, size: 14, color: Color(0xFF71717A)),
                  onPressed: () => _moveCard(index, 1),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 14, color: Color(0xFFF87171)),
                onPressed: () => widget.onCardDeleted(card.id),
              )
            ],
          ),
          const SizedBox(height: 4),
          const Divider(height: 1, color: Color(0xFF2E2E33)),
        ],
      ),
    );
  }

  Widget _buildCardContent(models.Card card) {
    final index = _cardIndex(card);
    final displayIndex = index + 1;
    switch (card.type) {
      case 'markdown':
        final meta = CardMetadata.fromJsonString(card.comment);
        final activePreset = colorPresets[meta.color] ?? colorPresets['default']!;
        return MarkdownCard(
          card: card,
          onContentChanged: (content) => widget.onCardUpdated(card.id, content),
          cardIndex: displayIndex,
          textColor: activePreset.text,
          textMutedColor: activePreset.textMuted,
        );
      case 'image':
        return ImageCard(
          card: card,
          onContentChanged: (content) => widget.onCardUpdated(card.id, content),
          cardIndex: displayIndex,
          dbService: widget.dbService,
        );
      case 'subpage_link':
        final meta = CardMetadata.fromJsonString(card.comment);
        final activePreset = colorPresets[meta.color] ?? colorPresets['default']!;

        return SubpageLinkCard(
          card: card,
          allPages: widget.allPages,
          currentPage: widget.selectedPage,
          onNavigate: widget.onNavigateToPage,
          onContentChanged: (content) => widget.onCardUpdated(card.id, content),
          onCreateNewPage: widget.onCreateNewPage,
          cardIndex: displayIndex,
          dbService: widget.dbService,
          textColor: activePreset.text,
          borderColor: activePreset.border,
          textMutedColor: activePreset.textMuted,
          onLongPress: () => _showBlockOptionsMenu(card, index),
        );
      case 'code':
        return CodeCard(
          card: card,
          onContentChanged: (content) => widget.onCardUpdated(card.id, content),
          cardIndex: displayIndex,
        );
      case 'sites':
        return SitesCard(
          card: card,
          onContentChanged: (content) => widget.onCardUpdated(card.id, content),
          cardIndex: displayIndex,
        );
      default:
        final meta = CardMetadata.fromJsonString(card.comment);
        final activePreset = colorPresets[meta.color] ?? colorPresets['default']!;
        return MarkdownCard(
          card: card,
          onContentChanged: (content) => widget.onCardUpdated(card.id, content),
          cardIndex: displayIndex,
          textColor: activePreset.text,
          textMutedColor: activePreset.textMuted,
        );
    }
  }

  void _showBlockOptionsMenu(models.Card card, int index) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF202020),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final meta = CardMetadata.fromJsonString(card.comment);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                child: Text(
                  'Block #${index + 1} (${card.type.toUpperCase()}) Options',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.drive_file_move_outlined, color: Color(0xFF818CF8)),
                title: const Text('Move Block to another Page', style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text('Move this card inside another page', style: TextStyle(color: Colors.grey, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showMoveBlockDialog(card);
                },
              ),
              ListTile(
                leading: const Icon(Icons.palette_outlined, color: Color(0xFF818CF8)),
                title: const Text('Change Block Color', style: TextStyle(color: Colors.white, fontSize: 14)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showColorPickerDialog(card, meta);
                },
              ),
              if (card.type == 'markdown')
                ListTile(
                  leading: const Icon(Icons.comment_outlined, color: Color(0xFF818CF8)),
                  title: const Text('Comments / Notes', style: TextStyle(color: Colors.white, fontSize: 14)),
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CommentsScreen(
                          card: card,
                          cardIndex: index + 1,
                          serverService: widget.serverService,
                          onCommentsUpdated: () {
                            widget.onCardUpdated(card.id, card.content);
                          },
                        ),
                      ),
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Delete Block', style: TextStyle(color: Colors.redAccent, fontSize: 14)),
                onTap: () {
                  Navigator.pop(ctx);
                  widget.onCardDeleted(card.id);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showColorPickerDialog(models.Card card, CardMetadata meta) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF202020),
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: colorPresets.entries.map((entry) {
            return ListTile(
              leading: Icon(Icons.circle, color: entry.value.textMuted),
              title: Text(entry.value.label, style: const TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);
                final newMeta = CardMetadata(color: entry.key, comments: meta.comments);
                await widget.serverService.updateCard(id: card.id, comment: newMeta.toJsonString());
                await widget.onCardUpdated(card.id, card.content);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showMoveBlockDialog(models.Card card) {
    final allPages = widget.allPages;
    final selectedPage = widget.selectedPage;

    final subpages = allPages.where((p) => p.parentId == selectedPage.id && p.relationType != 'sidepage' && p.id != selectedPage.id).toList();
    final neighbors = allPages.where((p) => p.parentId == selectedPage.parentId && p.id != selectedPage.id && p.relationType != 'sidepage').toList();
    final excludedIds = {selectedPage.id, ...subpages.map((p) => p.id), ...neighbors.map((p) => p.id)};
    final otherPages = allPages.where((p) => !excludedIds.contains(p.id) && p.relationType != 'sidepage').toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        title: const Text('Move Block To...', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          height: 350,
          child: ListView(
            children: [
              if (subpages.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Text('SUBPAGES / LINKS INSIDE THIS PAGE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF818CF8))),
                ),
                ...subpages.map((page) => _buildPageMoveTile(ctx, card, page)),
                const Divider(color: Color(0xFF2C2C2C)),
              ],
              if (neighbors.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Text('NEIGHBOR PAGES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                ),
                ...neighbors.map((page) => _buildPageMoveTile(ctx, card, page)),
                const Divider(color: Color(0xFF2C2C2C)),
              ],
              if (otherPages.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Text('OTHER PAGES', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                ),
                ...otherPages.map((page) => _buildPageMoveTile(ctx, card, page)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _buildPageMoveTile(BuildContext dialogCtx, models.Card card, DbPage page) {
    return ListTile(
      dense: true,
      leading: PageIcon(
        emoji: page.emoji,
        size: 16,
        dbService: widget.dbService,
      ),
      title: Text(
        page.title.isEmpty ? 'Untitled' : page.title,
        style: const TextStyle(fontSize: 13, color: Colors.white),
      ),
      onTap: () async {
        Navigator.pop(dialogCtx);
        await widget.serverService.updateCard(
          id: card.id,
          pageId: page.id,
        );
        await widget.onCardUpdated(card.id, card.content);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Moved block to "${page.title.isEmpty ? 'Untitled' : page.title}"')),
          );
        }
      },
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
              _addBlockOption(ctx, 'Markdown', 'Write formatted text', Icons.text_fields, 'markdown', '', index),
              _addBlockOption(ctx, 'Image', 'Embed visual images', Icons.image_outlined, 'image', '', index),
              _addBlockOption(ctx, 'Subpage Link', 'Create nested references', Icons.link, 'subpage_link', '', index),
              _addBlockOption(ctx, 'Code Block', 'Syntax-highlighted code', Icons.code, 'code', 'javascript\nconsole.log("Hello!");\n', index),
              _addBlockOption(ctx, 'HTML Site', 'Render custom local template widgets', Icons.web, 'sites', '{"name": "Site Widget", "html": "<h1>Hello Cero Sandbox</h1>"}', index),
              _addBlockOption(ctx, 'Section Divider', 'Full-width section header', Icons.title_outlined, 'section', 'New Section', index),
            ],
          ),
        ),
      ),
    );
  }

  Widget _addBlockOption(BuildContext ctx, String title, String subtitle, IconData icon, String type, String initialContent, int index) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF818CF8)),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 11)),
      onTap: () {
        Navigator.pop(ctx);
        if (_isPaginatedView) {
          _pendingBlockIndex = index;
        }
        widget.onCardAdded(widget.selectedPage.id, type, initialContent, insertAt: index);
      },
    );
  }
}
