import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import '../models/card_model.dart' as models;
import '../services/server_service.dart';
import '../utils/markdown_utils.dart';

class ReadingScreen extends StatefulWidget {
  final models.Card card;
  final int cardIndex;
  final ServerService? serverService;

  const ReadingScreen({
    super.key,
    required this.card,
    required this.cardIndex,
    this.serverService,
  });

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  bool _showScratchpad = false;
  bool _showTally = false;
  final TextEditingController _scratchpadController = TextEditingController();
  final FocusNode _scratchpadFocusNode = FocusNode();
  bool _scratchpadPreviewMode = false;
  Timer? _scratchpadSaveTimer;
  double _scratchpadWidth = 320.0;
  double _scratchpadHeight = 240.0;
  bool _scratchpadHorizontalLayout = false;

  final TextEditingController _newTallyNameController = TextEditingController();
  final ScrollController _tallyScrollController = ScrollController();
  List<models.Card> _tallyCards = [];

  @override
  void initState() {
    super.initState();
    if (widget.serverService != null) {
      _loadScratchpad();
      _loadTally();
      widget.serverService!.addListener(_onServerStateChanged);
      _scratchpadController.addListener(_saveScratchpadDebounced);
    }
  }

  @override
  void dispose() {
    if (widget.serverService != null) {
      widget.serverService!.removeListener(_onServerStateChanged);
      _scratchpadSaveTimer?.cancel();
      _scratchpadController.dispose();
      _scratchpadFocusNode.dispose();
      _newTallyNameController.dispose();
      _tallyScrollController.dispose();
    }
    super.dispose();
  }

  void _onServerStateChanged() {
    if (mounted) {
      setState(() {
        _syncRemoteScratchpad();
        _syncRemoteTally();
      });
    }
  }

  Future<void> _loadScratchpad() async {
    try {
      final cards = await widget.serverService!.getCards('global-scratchpad');
      if (cards.isNotEmpty) {
        _scratchpadController.text = cards.first.content;
      }
    } catch (e) {
      debugPrint('Error loading scratchpad: $e');
    }
  }

  Future<void> _saveScratchpad() async {
    try {
      await widget.serverService!.updateCard(
        id: 'global-scratchpad-card',
        pageId: 'global-scratchpad',
        content: _scratchpadController.text,
      );
    } catch (e) {
      debugPrint('Error saving scratchpad: $e');
    }
  }

  void _saveScratchpadDebounced() {
    _scratchpadSaveTimer?.cancel();
    _scratchpadSaveTimer = Timer(const Duration(milliseconds: 400), () {
      _saveScratchpad();
    });
  }

  Future<void> _syncRemoteScratchpad() async {
    try {
      final cards = await widget.serverService!.getCards('global-scratchpad');
      if (cards.isNotEmpty) {
        final remoteContent = cards.first.content;
        if (!_scratchpadFocusNode.hasFocus && _scratchpadController.text != remoteContent) {
          _scratchpadController.text = remoteContent;
        }
      }
    } catch (_) {}
  }

  Future<void> _loadTally() async {
    try {
      final cards = await widget.serverService!.getCards('global-tally');
      if (mounted) {
        setState(() {
          _tallyCards = cards;
        });
      }
    } catch (e) {
      debugPrint('Error loading tallies: $e');
    }
  }

  Future<void> _syncRemoteTally() async {
    try {
      final cards = await widget.serverService!.getCards('global-tally');
      if (mounted) {
        setState(() {
          _tallyCards = cards;
        });
      }
    } catch (_) {}
  }

  Widget _buildScratchpadPane() {
    return Container(
      color: const Color(0xFF131313),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              border: Border(bottom: BorderSide(color: Color(0xFF2C2C2C))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '📝 SCRATCHPAD',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF818CF8),
                    letterSpacing: 0.5,
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _scratchpadHorizontalLayout ? Icons.border_bottom_outlined : Icons.border_left_outlined,
                        size: 14,
                        color: Colors.grey,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Toggle Dock Position (Side / Bottom)',
                      onPressed: () {
                        setState(() {
                          _scratchpadHorizontalLayout = !_scratchpadHorizontalLayout;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        setState(() {
                          _scratchpadPreviewMode = false;
                        });
                      },
                      child: Text(
                        'Write',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: !_scratchpadPreviewMode ? const Color(0xFF818CF8) : Colors.grey,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        setState(() {
                          _scratchpadPreviewMode = true;
                        });
                      },
                      child: Text(
                        'Preview',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: _scratchpadPreviewMode ? const Color(0xFF818CF8) : Colors.grey,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 14),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        setState(() {
                          _showScratchpad = false;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _scratchpadPreviewMode
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: _scratchpadController.text.trim().isEmpty
                        ? const Center(
                            child: Text(
                              'No content to preview. Type something in the Write tab!',
                              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          )
                        : GptMarkdown(
                            formatMath(_scratchpadController.text),
                            style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFFCBD5E1)),
                          ),
                  )
                : TextField(
                    controller: _scratchpadController,
                    focusNode: _scratchpadFocusNode,
                    maxLines: null,
                    style: const TextStyle(fontSize: 12, height: 1.5, color: Colors.white, fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      hintText: 'Take quick notes here while reading...',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(12),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTallyPane() {
    return Container(
      color: const Color(0xFF131313),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              border: Border(bottom: BorderSide(color: Color(0xFF2C2C2C))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '🔢 TALLIES',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF818CF8),
                    letterSpacing: 0.5,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    setState(() {
                      _showTally = false;
                    });
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newTallyNameController,
                    style: const TextStyle(fontSize: 12, color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'New Tally Name...',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: Color(0xFF191919),
                      border: OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF2C2C2C)),
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF2C2C2C)),
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF818CF8)),
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                      ),
                    ),
                    onSubmitted: (val) => _addTallyItem(),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Color(0xFF818CF8), size: 24),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: _addTallyItem,
                ),
              ],
            ),
          ),
          Expanded(
            child: _tallyCards.isEmpty
                ? const Center(
                    child: Text(
                      'No tallies yet. Add one above!',
                      style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                    ),
                  )
                : ListView.builder(
                    controller: _tallyScrollController,
                    itemCount: _tallyCards.length,
                    itemBuilder: (context, idx) {
                      final card = _tallyCards[idx];
                      String name = 'Tally';
                      int count = 0;
                      try {
                        final decoded = jsonDecode(card.content) as Map<String, dynamic>;
                        name = decoded['name'] ?? 'Tally';
                        count = decoded['count'] ?? 0;
                      } catch (_) {
                        name = card.comment.isEmpty ? 'Tally' : card.comment;
                        count = int.tryParse(card.content) ?? 0;
                      }

                      return Card(
                        color: const Color(0xFF1E1E1E),
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: const BorderSide(color: Color(0xFF2C2C2C)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.redAccent),
                                    onPressed: count > 0 ? () => _updateTallyValue(card, count - 1) : null,
                                  ),
                                  Container(
                                    constraints: const BoxConstraints(minWidth: 32),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '$count',
                                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add_circle_outline, size: 20, color: Colors.greenAccent),
                                    onPressed: () => _updateTallyValue(card, count + 1),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.grey),
                                    onPressed: () => _deleteTallyItem(card.id),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _addTallyItem() async {
    final name = _newTallyNameController.text.trim();
    if (name.isEmpty) return;

    _newTallyNameController.clear();
    try {
      final jsonContent = jsonEncode({'name': name, 'count': 0});
      await widget.serverService!.addCard(
        pageId: 'global-tally',
        type: 'tally',
        content: jsonContent,
        insertAt: _tallyCards.length,
      );
      await _loadTally();
    } catch (e) {
      debugPrint('Error adding tally item: $e');
    }
  }

  Future<void> _updateTallyValue(models.Card card, int newValue) async {
    try {
      final decoded = jsonDecode(card.content) as Map<String, dynamic>;
      final updatedJson = jsonEncode({
        'name': decoded['name'] ?? 'Tally',
        'count': newValue,
      });
      await widget.serverService!.updateCard(
        id: card.id,
        pageId: 'global-tally',
        content: updatedJson,
      );
      await _loadTally();
    } catch (e) {
      debugPrint('Error updating tally value: $e');
    }
  }

  Future<void> _deleteTallyItem(String cardId) async {
    try {
      await widget.serverService!.deleteCard(cardId);
      await _loadTally();
    } catch (e) {
      debugPrint('Error deleting tally item: $e');
    }
  }

  Widget _buildReaderBody() {
    if (widget.card.type == 'code') {
      String codeLang = 'javascript';
      String codeContent = widget.card.content;
      if (codeContent.contains('\n')) {
        codeLang = codeContent.substring(0, codeContent.indexOf('\n')).trim().toLowerCase();
        codeContent = codeContent.substring(codeContent.indexOf('\n') + 1);
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Container(
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
                    children: highlightCode(codeContent, codeLang),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
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
              formatMath(widget.card.content),
              style: const TextStyle(
                fontSize: 16,
                height: 1.8,
                color: Color(0xFFE2E8F0),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget readerBody = _buildReaderBody();

    final bool showSplitPane = _showScratchpad || _showTally;
    final Widget splitPaneWidget = _showScratchpad ? _buildScratchpadPane() : _buildTallyPane();

    Widget mainBody;
    if (showSplitPane) {
      if (_scratchpadHorizontalLayout) {
        mainBody = Row(
          children: [
            Expanded(child: readerBody),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _scratchpadWidth = (_scratchpadWidth - details.delta.dx).clamp(200.0, 600.0);
                });
              },
              child: Container(
                width: 6,
                color: Colors.transparent,
                child: Center(
                  child: Container(width: 1, color: const Color(0xFF2C2C2C)),
                ),
              ),
            ),
            SizedBox(
              width: _scratchpadWidth,
              child: splitPaneWidget,
            ),
          ],
        );
      } else {
        mainBody = Column(
          children: [
            Expanded(child: readerBody),
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragUpdate: (details) {
                setState(() {
                  _scratchpadHeight = (_scratchpadHeight - details.delta.dy).clamp(120.0, 500.0);
                });
              },
              child: Container(
                height: 12,
                color: Colors.transparent,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(height: 1, color: const Color(0xFF2C2C2C)),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFF202020),
                        borderRadius: BorderRadius.circular(2),
                        border: Border.all(color: const Color(0xFF3E3E3E)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: _scratchpadHeight,
              child: splitPaneWidget,
            ),
          ],
        );
      }
    } else {
      mainBody = readerBody;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF141414),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Block #${widget.cardIndex}',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          if (widget.serverService != null) ...[
            IconButton(
              icon: Icon(
                _showScratchpad ? Icons.note_alt : Icons.note_alt_outlined,
                color: _showScratchpad ? const Color(0xFF818CF8) : null,
              ),
              tooltip: 'Toggle Scratchpad',
              onPressed: () {
                setState(() {
                  _showScratchpad = !_showScratchpad;
                  if (_showScratchpad) _showTally = false;
                });
              },
            ),
            IconButton(
              icon: Icon(
                _showTally ? Icons.plus_one : Icons.plus_one_outlined,
                color: _showTally ? const Color(0xFF818CF8) : null,
              ),
              tooltip: 'Toggle Tally Page',
              onPressed: () {
                setState(() {
                  _showTally = !_showTally;
                  if (_showTally) _showScratchpad = false;
                });
              },
            ),
          ],
        ],
      ),
      body: SafeArea(child: mainBody),
    );
  }
}
