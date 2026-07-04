import 'package:flutter/material.dart';
import '../models/page_model.dart';
import '../models/card_model.dart' as models;
import 'markdown_card.dart';
import 'image_card.dart';
import 'subpage_link_card.dart';

class CardColumn extends StatefulWidget {
  final List<models.Card> cards;
  final List<DbPage> allPages;
  final DbPage selectedPage;
  final ValueChanged<DbPage> onNavigateToPage;
  final Future<void> Function(String cardId, String content) onCardUpdated;
  final Future<void> Function(String pageId, String type, String content) onCardAdded;
  final Future<void> Function(String cardId) onCardDeleted;
  final Future<void> Function(List<String> cardIds) onCardsReordered;
  final ValueChanged<String>? onCreateNewPage;

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
  });

  @override
  State<CardColumn> createState() => _CardColumnState();
}

class _CardColumnState extends State<CardColumn> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            itemCount: widget.cards.length,
            onReorder: _onReorder,
            itemBuilder: (context, index) {
              final card = widget.cards[index];
              return Column(
                key: ValueKey(card.id),
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildInsertButton(index),
                  _buildCard(card, index),
                  if (index == widget.cards.length - 1) _buildInsertButton(index + 1),
                ],
              );
            },
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
            child: _buildCardContent(card),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildCardContent(card),
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
            child: _buildCardContent(card),
          );
        },
      ),
    );
  }

  Widget _buildCardContent(models.Card card) {
    switch (card.type) {
      case 'image':
        return ImageCard(
          card: card,
          onContentChanged: (content) => widget.onCardUpdated(card.id, content),
          onDelete: () => widget.onCardDeleted(card.id),
          onMoveUp: _cardIndex(card) > 0 ? () => _moveCard(_cardIndex(card), -1) : null,
          onMoveDown: _cardIndex(card) < widget.cards.length - 1 ? () => _moveCard(_cardIndex(card), 1) : null,
        );
      case 'subpage_link':
        return SubpageLinkCard(
          card: card,
          allPages: widget.allPages,
          onNavigate: widget.onNavigateToPage,
          onContentChanged: (content) => widget.onCardUpdated(card.id, content),
          onCreateNewPage: widget.onCreateNewPage,
          onDelete: () => widget.onCardDeleted(card.id),
          onMoveUp: _cardIndex(card) > 0 ? () => _moveCard(_cardIndex(card), -1) : null,
          onMoveDown: _cardIndex(card) < widget.cards.length - 1 ? () => _moveCard(_cardIndex(card), 1) : null,
        );
      default:
        return MarkdownCard(
          card: card,
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
      builder: (ctx) => SafeArea(
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
          ],
        ),
      ),
    );
  }
}
