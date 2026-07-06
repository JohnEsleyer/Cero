import 'package:flutter/material.dart';
import '../models/page_model.dart';
import '../models/card_model.dart' as models;

class SubpageLinkCard extends StatefulWidget {
  final models.Card card;
  final List<DbPage> allPages;
  final DbPage? currentPage;
  final ValueChanged<DbPage> onNavigate;
  final ValueChanged<String> onContentChanged;
  final Future<DbPage?> Function(String parentId)? onCreateNewPage;
  final VoidCallback? onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final int? cardIndex;

  const SubpageLinkCard({
    super.key,
    required this.card,
    required this.allPages,
    this.currentPage,
    required this.onNavigate,
    required this.onContentChanged,
    this.onCreateNewPage,
    this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
    this.cardIndex,
  });

  @override
  State<SubpageLinkCard> createState() => _SubpageLinkCardState();
}

class _SubpageLinkCardState extends State<SubpageLinkCard> {
  bool _isEditing = false;

  DbPage? get _linkedPage {
    if (widget.card.content.isEmpty) return null;
    try {
      return widget.allPages.firstWhere((p) => p.id == widget.card.content);
    } catch (_) {
      return null;
    }
  }

  List<DbPage> get _candidates {
    final currentPage = widget.currentPage;
    if (currentPage == null) {
      return widget.allPages
          .where(
            (p) => p.id != widget.card.pageId && p.relationType != 'sidepage',
          )
          .toList();
    }

    final directChildrenIds = widget.allPages
        .where((p) =>
            p.parentId == currentPage.id && p.relationType != 'sidepage')
        .map((p) => p.id)
        .toSet();

    return widget.allPages.where((p) {
      if (p.id == widget.card.pageId || p.relationType == 'sidepage') {
        return false;
      }
      if (p.parentId == currentPage.id) return true;
      return directChildrenIds.contains(p.parentId);
    }).toList();
  }

  void _handleTap() {
    final linked = _linkedPage;
    if (linked != null && !_isEditing) {
      widget.onNavigate(linked);
    }
  }

  void _openPicker() {
    setState(() => _isEditing = true);
    _showPagePicker();
  }

  @override
  Widget build(BuildContext context) {
    final linked = _linkedPage;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF2E2E2E), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(linked),
          linked != null && !_isEditing
              ? _buildLinkTile(linked)
              : _buildPlaceholder(context),
        ],
      ),
    );
  }

  Widget _buildHeader(DbPage? linked) {
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
          const Icon(Icons.link, size: 16, color: Color(0xFF64748B)),
          const SizedBox(width: 6),
          const Text(
            'Subpage Link',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 16),
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            color: const Color(0xFF818CF8),
            tooltip: 'Configure link',
            onPressed: () {
              if (linked != null) {
                _openPicker();
              } else {
                _showPagePicker();
              }
            },
          ),
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

  Widget _buildLinkTile(DbPage page) {
    return InkWell(
      onTap: _handleTap,
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Text(page.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    page.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to open',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF64748B)),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    return InkWell(
      onTap: () => _showPagePicker(),
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        alignment: Alignment.centerLeft,
        child: Text(
          'Tap to link a subpage...',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      ),
    );
  }

  void _showPagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF202020),
      isScrollControlled: true,
      builder: (ctx) => _PagePickerSheet(
        candidates: _candidates,
        onSelect: (page) {
          widget.onContentChanged(page.id);
          setState(() => _isEditing = false);
          Navigator.pop(ctx);
        },
        onCreateNew: () async {
          Navigator.pop(ctx);
          if (widget.onCreateNewPage != null) {
            final newPage = await widget.onCreateNewPage!(widget.card.pageId);
            if (newPage != null) {
              widget.onContentChanged(newPage.id);
            }
          }
          if (mounted) setState(() => _isEditing = false);
        },
      ),
    ).then((_) {
      if (mounted) setState(() => _isEditing = false);
    });
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
}

class _PagePickerSheet extends StatefulWidget {
  final List<DbPage> candidates;
  final ValueChanged<DbPage> onSelect;
  final VoidCallback onCreateNew;

  const _PagePickerSheet({
    required this.candidates,
    required this.onSelect,
    required this.onCreateNew,
  });

  @override
  State<_PagePickerSheet> createState() => _PagePickerSheetState();
}

class _PagePickerSheetState extends State<_PagePickerSheet> {
  String _searchQuery = '';

  List<DbPage> get _filtered {
    if (_searchQuery.isEmpty) return widget.candidates;
    final q = _searchQuery.toLowerCase();
    return widget.candidates
        .where((p) => p.title.toLowerCase().contains(q) || p.emoji.contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollController) => Column(
        children: [
          const Focus(autofocus: true, child: SizedBox.shrink()),
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Link a subpage',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.grey,
                        size: 20,
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Search bar
                TextField(
                  autofocus: false,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search pages...',
                    hintStyle: TextStyle(color: Colors.grey.shade600),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Colors.grey,
                      size: 18,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF3E3E3E)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF3E3E3E)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF818CF8)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Create new page button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onCreateNew,
                icon: const Icon(Icons.add, size: 16, color: Color(0xFF818CF8)),
                label: const Text(
                  'Create New Page',
                  style: TextStyle(color: Color(0xFF818CF8), fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  side: const BorderSide(color: Color(0xFF3E3E3E)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 4),

          // Page list
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        _searchQuery.isEmpty
                            ? 'No pages available'
                            : 'No pages match "$_searchQuery"',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    itemCount: _filtered.length,
                    itemBuilder: (_, i) {
                      final p = _filtered[i];
                      return ListTile(
                        leading: Text(
                          p.emoji,
                          style: const TextStyle(fontSize: 20),
                        ),
                        title: Text(
                          p.title,
                          style: const TextStyle(color: Colors.white),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        dense: true,
                        onTap: () => widget.onSelect(p),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
