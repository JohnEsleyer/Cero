import 'package:flutter/material.dart';
import '../models/page_model.dart';
import '../models/card_model.dart' as models;
import '../services/database_service.dart';
import 'page_icon.dart';

class SubpageLinkCard extends StatelessWidget {
  final models.Card card;
  final List<DbPage> allPages;
  final DbPage currentPage;
  final ValueChanged<DbPage> onNavigate;
  final ValueChanged<String> onContentChanged;
  final Future<DbPage?> Function(String parentId)? onCreateNewPage;
  final int cardIndex;
  final DatabaseService? dbService;

  final Color? textColor;
  final Color? borderColor;
  final Color? textMutedColor;

  const SubpageLinkCard({
    super.key,
    required this.card,
    required this.allPages,
    required this.currentPage,
    required this.onNavigate,
    required this.onContentChanged,
    this.onCreateNewPage,
    required this.cardIndex,
    this.dbService,
    this.textColor,
    this.borderColor,
    this.textMutedColor,
  });

  @override
  Widget build(BuildContext context) {
    final targetPageId = card.content;
    final DbPage? targetPage = targetPageId.isNotEmpty
        ? allPages.where((p) => p.id == targetPageId).firstOrNull
        : null;

    final Color resolvedText = textColor ?? const Color(0xFFCBD5E1);
    final Color resolvedBorder = borderColor ?? const Color(0xFF2C2C2C);
    final Color resolvedMuted = textMutedColor ?? const Color(0xFF71717A);

    String? coverUrl;
    if (targetPage != null) {
      try {
        coverUrl = (targetPage as dynamic).cover as String?;
      } catch (_) {}
    }

    final bool hasCover = coverUrl != null && coverUrl.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hasCover ? Colors.white.withOpacity(0.08) : resolvedBorder.withOpacity(0.4)),
        image: hasCover
            ? DecorationImage(
                image: NetworkImage(coverUrl),
                fit: BoxFit.cover,
              )
            : null,
        gradient: !hasCover
            ? const LinearGradient(
                colors: [Color(0xFF1E1E24), Color(0xFF2A2A35)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(hasCover ? 0.45 : 0.15),
              ),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: targetPage != null ? () => onNavigate(targetPage) : () => _showSelectPageDialog(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        PageIcon(
                          emoji: targetPage?.emoji ?? '🔗',
                          size: 14,
                          dbService: dbService,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            targetPage != null
                                ? (targetPage.title.isEmpty ? 'Untitled Page' : targetPage.title)
                                : 'Link subpage...',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              shadows: [
                                Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black),
                              ],
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (targetPage != null) ...[
                          const Text(
                            'Open',
                            style: TextStyle(
                              fontSize: 9.5,
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                              shadows: [Shadow(offset: Offset(0, 1), blurRadius: 4, color: Colors.black)],
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.arrow_forward_ios, size: 8, color: Colors.white70),
                        ],
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.settings, size: 12, color: Colors.white70),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _showSelectPageDialog(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSelectPageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        final candidates = allPages.where((p) => p.id != currentPage.id && p.parentId == currentPage.id).toList();

        return AlertDialog(
          backgroundColor: const Color(0xFF202020),
          title: const Text('Select Subpage', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: double.maxFinite,
            height: 250,
            child: candidates.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('No subpages found.', style: TextStyle(color: Colors.grey, fontSize: 11)),
                        const SizedBox(height: 12),
                        if (onCreateNewPage != null)
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF818CF8),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            onPressed: () async {
                              Navigator.pop(ctx);
                              final newPage = await onCreateNewPage!(currentPage.id);
                              if (newPage != null) {
                                onContentChanged(newPage.id);
                              }
                            },
                            child: const Text('Create New Subpage', style: TextStyle(fontSize: 10)),
                          ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: candidates.length,
                    itemBuilder: (cCtx, index) {
                      final page = candidates[index];
                      return ListTile(
                        dense: true,
                        leading: PageIcon(emoji: page.emoji, size: 14, dbService: dbService),
                        title: Text(page.title.isEmpty ? 'Untitled' : page.title, style: const TextStyle(fontSize: 12, color: Colors.white)),
                        onTap: () {
                          Navigator.pop(ctx);
                          onContentChanged(page.id);
                        },
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey, fontSize: 11)),
            ),
          ],
        );
      },
    );
  }
}
