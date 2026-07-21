import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'services/server_service.dart';
import 'models/page_model.dart';
import 'models/card_model.dart' as models;
import 'widgets/card_column.dart';
import 'widgets/page_icon.dart';
import 'widgets/cero_logo.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final serverService = ServerService();
  await serverService.init();

  runApp(MyApp(serverService: serverService));
}

class MyApp extends StatelessWidget {
  final ServerService serverService;

  const MyApp({super.key, required this.serverService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cero Journal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF191919),
        primaryColor: const Color(0xFF818CF8),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF818CF8),
          brightness: Brightness.dark,
          primary: const Color(0xFF818CF8),
          secondary: const Color(0xFF818CF8),
          surface: const Color(0xFF202020),
        ),
        cardTheme: const CardThemeData(color: Color(0xFF202020), elevation: 0),
        drawerTheme: const DrawerThemeData(backgroundColor: Color(0xFF202020)),
      ),
      home: MainJournalScreen(serverService: serverService),
    );
  }
}

class MainJournalScreen extends StatefulWidget {
  final ServerService serverService;

  const MainJournalScreen({super.key, required this.serverService});

  @override
  State<MainJournalScreen> createState() => _MainJournalScreenState();
}

class _MainJournalScreenState extends State<MainJournalScreen> {
  late final ServerService _serverService;

  DbPage? _selectedPage;
  final Set<String> _expandedPageIds = {};
  bool _showArchived = false;
  List<DbPage> _archivedPages = [];
  final List<String> _navigationHistory = [];
  final TextEditingController _titleController = TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  final ScrollController _cardScrollController = ScrollController();
  List<models.Card> _pageCards = [];
  List<DbPage> _sidePages = [];
  bool _isRefreshingPage = false;
  Timer? _saveDebounceTimer;
  final TextEditingController _clientIpController = TextEditingController();
  final TextEditingController _clientPinController = TextEditingController();
  bool _isClientModeTab = false;
  String _sidebarSearchQuery = '';

  bool _showScratchpad = false;
  final TextEditingController _scratchpadController = TextEditingController();
  final FocusNode _scratchpadFocusNode = FocusNode();
  bool _scratchpadPreviewMode = false;
  Timer? _scratchpadSaveTimer;
  double _scratchpadWidth = 320.0;
  double _scratchpadHeight = 240.0;
  bool _scratchpadHorizontalLayout = false;

  bool _showTally = false;
  final TextEditingController _newTallyNameController = TextEditingController();
  final ScrollController _tallyScrollController = ScrollController();
  List<models.Card> _tallyCards = [];

  List<String> _recentlyOpenedRootPageIds = [];

  @override
  void initState() {
    super.initState();
    _serverService = widget.serverService;
    _serverService.addListener(_onServerStateChanged);
    _loadScratchpad();
    _loadTally();
    _loadRecentlyOpened();
    _scratchpadController.addListener(_saveScratchpadDebounced);

    _clientIpController.text = _serverService.lastConnectedIp;
    _clientPinController.text = _serverService.lastConnectedPin;
  }

  Future<void> _loadRecentlyOpened() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/recently_opened_root_pages.txt');
      if (await file.exists()) {
        final content = await file.readAsString();
        if (mounted) {
          setState(() {
            _recentlyOpenedRootPageIds = content
                .split('\n')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading recently opened root pages: $e');
    }
  }

  Future<void> _saveRecentlyOpened() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/recently_opened_root_pages.txt');
      await file.writeAsString(_recentlyOpenedRootPageIds.join('\n'));
    } catch (e) {
      debugPrint('Error saving recently opened root pages: $e');
    }
  }

  @override
  void dispose() {
    _serverService.removeListener(_onServerStateChanged);
    _titleController.dispose();
    _titleFocusNode.dispose();
    _saveDebounceTimer?.cancel();
    _clientIpController.dispose();
    _clientPinController.dispose();
    _scratchpadSaveTimer?.cancel();
    _scratchpadController.dispose();
    _scratchpadFocusNode.dispose();
    _newTallyNameController.dispose();
    _tallyScrollController.dispose();
    super.dispose();
  }

  void _onServerStateChanged() {
    if (mounted) {
      setState(() {
        if (_clientIpController.text.isEmpty && _serverService.lastConnectedIp.isNotEmpty) {
          _clientIpController.text = _serverService.lastConnectedIp;
        }
        if (_clientPinController.text.isEmpty && _serverService.lastConnectedPin.isNotEmpty) {
          _clientPinController.text = _serverService.lastConnectedPin;
        }

        if (_selectedPage != null) {
          final updatedPage = _serverService.pages.firstWhere(
            (p) => p.id == _selectedPage!.id,
            orElse: () => _selectedPage!,
          );

          if (!_serverService.pages.any((p) => p.id == _selectedPage!.id)) {
            _selectedPage = null;
            _navigationHistory.clear();
            _pageCards = [];
          } else {
            _selectedPage = updatedPage;
            if (!_titleFocusNode.hasFocus) {
              _titleController.text = updatedPage.title;
            }
            _loadCardsForPage(updatedPage.id);
          }
        }

        _checkPendingConnections();
        _syncRemoteScratchpad();
        _syncRemoteTally();
      });
    }
  }

  Future<void> _loadScratchpad() async {
    try {
      final cards = await _serverService.getCards('global-scratchpad');
      if (cards.isNotEmpty) {
        _scratchpadController.text = cards.first.content;
      }
    } catch (e) {
      debugPrint('Error loading scratchpad: $e');
    }
  }

  Future<void> _saveScratchpad() async {
    try {
      await _serverService.updateCard(
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
      final cards = await _serverService.getCards('global-scratchpad');
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
      final cards = await _serverService.getCards('global-tally');
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
      final cards = await _serverService.getCards('global-tally');
      if (mounted) {
        setState(() {
          _tallyCards = cards;
        });
      }
    } catch (_) {}
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
      await _serverService.addCard(
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
      await _serverService.updateCard(
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
      await _serverService.deleteCard(cardId);
      await _loadTally();
    } catch (e) {
      debugPrint('Error deleting tally item: $e');
    }
  }

  Future<void> _loadCardsForPage(String pageId) async {
    try {
      final cards = await _serverService.getCards(pageId);
      final sidePages = await _serverService.getSidePages(pageId);
      if (mounted) {
        setState(() {
          _pageCards = cards;
          _sidePages = sidePages;
        });
      }
    } catch (e) {
      debugPrint('Error loading cards: $e');
    }
  }

  Future<void> _refreshSelectedPage() async {
    final page = _selectedPage;
    if (page == null || _isRefreshingPage) return;

    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    if (_selectedPage != null) {
      final newTitle = _titleController.text.trim().isEmpty
          ? 'Untitled'
          : _titleController.text.trim();

      _serverService.updatePage(
        id: _selectedPage!.id,
        title: newTitle,
        emoji: _selectedPage!.emoji,
      );
    }
    setState(() => _isRefreshingPage = true);

    try {
      if (!_serverService.isClientMode) {
        await _serverService.loadDatabaseState();
      }
      if (!mounted) return;

      final refreshedPage = _serverService.pages
          .where((candidate) => candidate.id == page.id)
          .firstOrNull;

      if (refreshedPage == null) {
        setState(() {
          _selectedPage = null;
          _navigationHistory.clear();
          _pageCards = [];
          _sidePages = [];
        });
        return;
      }

      _selectedPage = refreshedPage;
      if (!_titleFocusNode.hasFocus) {
        _titleController.text = refreshedPage.title;
      }
      await _loadCardsForPage(refreshedPage.id);
    } catch (e) {
      debugPrint('Error refreshing page: $e');
    } finally {
      if (mounted) {
        setState(() => _isRefreshingPage = false);
      }
    }
  }

  void _checkPendingConnections() {
    final pendingList = _serverService.pendingConnections;
    if (pendingList.isEmpty) return;

    for (int i = 0; i < pendingList.length; i++) {
      final pending = pendingList[i];
      _showPairingDialog(i, pending.remoteAddress);
    }
  }

  void _showPairingDialog(int index, String remoteAddress) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        title: const Text('Pairing Request'),
        content: Text(
          'Device at $remoteAddress wants to connect to your journal.\n\nAllow this connection?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              _serverService.rejectPendingClient(index);
              Navigator.pop(ctx);
            },
            child: const Text(
              'Deny',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              _serverService.approvePendingClient(index);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF818CF8),
              foregroundColor: Colors.white,
            ),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
  }

  void _selectPage(DbPage page, {bool pushToHistory = true}) {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    if (_selectedPage != null) {
      final newTitle = _titleController.text.trim().isEmpty
          ? 'Untitled'
          : _titleController.text.trim();

      _serverService.updatePage(
        id: _selectedPage!.id,
        title: newTitle,
        emoji: _selectedPage!.emoji,
      );
    }
    _titleFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();

    if (pushToHistory &&
        _selectedPage != null &&
        _selectedPage!.id != page.id) {
      _navigationHistory.add(_selectedPage!.id);
    }

    if (page.parentId == null && page.relationType != 'sidepage' && page.relationType != 'scratchpad' && page.relationType != 'tally') {
      setState(() {
        _recentlyOpenedRootPageIds.remove(page.id);
        _recentlyOpenedRootPageIds.insert(0, page.id);
      });
      _saveRecentlyOpened();
    }

    setState(() {
      _selectedPage = page;
      _titleController.text = page.title;
      _pageCards = [];
      _sidePages = [];
    });
    _loadCardsForPage(page.id);
  }

  void _goBack() {
    while (_navigationHistory.isNotEmpty) {
      final prevId = _navigationHistory.removeLast();
      final exists = _serverService.pages.any((p) => p.id == prevId);
      if (exists) {
        final prevPage = _serverService.pages.firstWhere((p) => p.id == prevId);
        _selectPage(prevPage, pushToHistory: false);
        return;
      }
    }
  }

  void _saveCurrentPage() {
    if (_selectedPage == null) return;

    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _saveDebounceTimer?.cancel();
      _saveDebounceTimer = null;
      if (_selectedPage != null) {
        final newTitle = _titleController.text.trim().isEmpty
            ? 'Untitled'
            : _titleController.text.trim();

        _serverService.updatePage(
          id: _selectedPage!.id,
          title: newTitle,
          emoji: _selectedPage!.emoji,
        );
      }
    });
  }

  void _saveCurrentPageImmediate() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    if (_selectedPage != null) {
      final newTitle = _titleController.text.trim().isEmpty
          ? 'Untitled'
          : _titleController.text.trim();

      _serverService.updatePage(
        id: _selectedPage!.id,
        title: newTitle,
        emoji: _selectedPage!.emoji,
      );
    }
  }

  Future<DbPage?> _createSubpage(
    String? parentId, {
    String relationType = 'subpage',
  }) async {
    final newPage = await _serverService.addPage(
      parentId: parentId,
      relationType: relationType,
      title: 'New Page',
      emoji: '',
    );

    await _serverService.addCard(
      pageId: newPage.id,
      type: 'markdown',
      content: '# New Page\n\nStart writing markdown here...',
    );

    _selectPage(newPage);

    if (parentId != null) {
      setState(() {
        _expandedPageIds.add(parentId);
      });
    }

    return newPage;
  }

  void _archiveSelectedPage(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        title: const Text('Archive Page?'),
        content: const Text(
          'This will archive this page and all subpages nested inside it. You can restore them later from the trash.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              if (_selectedPage?.id == id) {
                setState(() {
                  _selectedPage = null;
                  _navigationHistory.clear();
                });
              }
              await _serverService.deletePage(id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMoveDialog() async {
    final allPages = _serverService.pages;
    final currentPage = _selectedPage;
    if (currentPage == null) return;

    final selectedParent = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        title: const Text('Move Page To...'),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView(
            children: [
              ListTile(
                dense: true,
                leading: const Icon(
                  Icons.folder_off_outlined,
                  color: Colors.grey,
                ),
                title: const Text(
                  'Root Level (No Parent)',
                  style: TextStyle(fontSize: 13),
                ),
                onTap: () => Navigator.pop(ctx, ''),
              ),
              ...allPages
                  .where(
                    (p) =>
                        p.id != currentPage.id && p.relationType != 'sidepage',
                  )
                  .map(
                    (page) => ListTile(
                      dense: true,
                      leading: PageIcon(
                        emoji: page.emoji,
                        size: 16,
                        dbService: _serverService.dbService,
                      ),
                      title: Text(
                        page.title.isEmpty ? 'Untitled' : page.title,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: page.parentId != null
                          ? const Text(
                              'subpage',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            )
                          : null,
                      onTap: () => Navigator.pop(ctx, page.id),
                    ),
                  ),
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

    if (selectedParent != null) {
      final newParentId = selectedParent.isEmpty ? null : selectedParent;
      await _serverService.movePage(currentPage.id, newParentId);
    }
  }

  void _showEmojiPicker() {
    if (_selectedPage == null) return;

    final parentId = _selectedPage!.parentId;
    final parentPage = parentId != null
        ? _serverService.pages.where((p) => p.id == parentId).firstOrNull
        : null;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF202020),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Select Page Icon',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Icon(Icons.add_photo_alternate_outlined, size: 48, color: Color(0xFF818CF8)),
            const SizedBox(height: 12),
            const Text(
              'Use Custom Page Icon',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 6),
            const Text(
              "Import an image from your system or use an online URL as this page's icon.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                try {
                  final result = await FilePicker.platform.pickFiles(type: FileType.image);
                  if (result != null && result.files.single.path != null) {
                    final file = File(result.files.single.path!);
                    final bytes = await file.readAsBytes();
                    final name = result.files.single.name;
                    final filename = await _serverService.dbService.saveImage(bytes, name);
                    setState(() {
                      _selectedPage = _selectedPage!.copyWith(emoji: filename);
                    });
                    _saveCurrentPageImmediate();
                    Navigator.pop(context);
                  }
                } catch (e) {
                  debugPrint('Error picking icon image: $e');
                }
              },
              icon: const Icon(Icons.photo_library),
              label: const Text('Pick Image from System'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF818CF8),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                final urlController = TextEditingController();
                showDialog(
                  context: context,
                  builder: (dialogCtx) => AlertDialog(
                    backgroundColor: const Color(0xFF202020),
                    title: const Text('Enter Icon URL', style: TextStyle(color: Colors.white, fontSize: 14)),
                    content: TextField(
                      controller: urlController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'https://example.com/icon.png',
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 12),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF3E3E3E))),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF818CF8))),
                      ),
                      autofocus: true,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogCtx),
                        child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                      ),
                      TextButton(
                        onPressed: () {
                          final url = urlController.text.trim();
                          if (url.isNotEmpty) {
                            setState(() {
                              _selectedPage = _selectedPage!.copyWith(emoji: url);
                            });
                            _saveCurrentPageImmediate();
                            Navigator.pop(dialogCtx);
                            Navigator.pop(context);
                          }
                        },
                        child: const Text('Apply', style: TextStyle(color: Color(0xFF818CF8))),
                      ),
                    ],
                  ),
                );
              },
              icon: const Icon(Icons.link),
              label: const Text('Use Image URL'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF818CF8),
                side: const BorderSide(color: Color(0xFF3E3E3E)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
            if (parentPage != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedPage = _selectedPage!.copyWith(emoji: parentPage.emoji);
                  });
                  _saveCurrentPageImmediate();
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.copy),
                label: Text('Inherit Parent Icon ("${parentPage.title.isEmpty ? 'Untitled' : parentPage.title}")'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF818CF8),
                  side: const BorderSide(color: Color(0xFF3E3E3E)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedPage = _selectedPage!.copyWith(emoji: '');
                });
                _saveCurrentPageImmediate();
                Navigator.pop(context);
              },
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              label: const Text('Remove Custom Icon', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );
  }


  List<DbPage> _getPagePath(DbPage? page) {
    if (page == null) return [];
    final List<DbPage> path = [page];
    String? parentId = page.parentId;
    int depth = 0;
    while (parentId != null && depth < 20) {
      final pid = parentId;
      final parents = _serverService.pages.where((p) => p.id == pid).toList();
      if (parents.isNotEmpty) {
        final parent = parents.first;
        path.insert(0, parent);
        parentId = parent.parentId;
      } else {
        break;
      }
      depth++;
    }
    return path;
  }

  Widget _buildAppBarTitle() {
    if (_selectedPage == null) {
      return Row(
        children: [
          const CeroLogo(size: 18),
          const SizedBox(width: 8),
          const Text(
            'Cero',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
          ),
          const SizedBox(width: 8),
          _buildLinkIndicator(),
        ],
      );
    }

    final path = _getPagePath(_selectedPage);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Navigator.canPop(context) ? const SizedBox.shrink() : SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: path.asMap().entries.map((entry) {
              final index = entry.key;
              final page = entry.value;
              final isLast = index == path.length - 1;

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (index > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4.0),
                      child: Text(
                        '/',
                        style: TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ),
                  PageIcon(
                    emoji: page.emoji,
                    size: 10,
                    dbService: _serverService.dbService,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    page.title.isEmpty ? 'Untitled' : page.title,
                    style: TextStyle(
                      fontSize: 10,
                      color: isLast ? const Color(0xFF818CF8) : Colors.grey,
                      fontWeight: isLast ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Expanded(
              child: Text(
                _selectedPage!.title.isEmpty
                    ? 'Untitled'
                    : _selectedPage!.title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            _buildLinkIndicator(),
          ],
        ),
      ],
    );
  }

  Widget _buildLinkIndicator() {
    final isActive = _serverService.isRunning ||
        (_serverService.isClientMode && _serverService.isClientPaired);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: isActive
            ? Colors.green.withOpacity(0.1)
            : Colors.grey.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isActive ? 'LINK ON' : 'LINK OFF',
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: isActive ? Colors.green : Colors.grey,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allPages = _serverService.pages;
    final rootPages = allPages
        .where((p) => p.parentId == null && p.relationType != 'sidepage' && p.relationType != 'scratchpad' && p.relationType != 'tally')
        .toList();

    rootPages.sort((a, b) {
      final idxA = _recentlyOpenedRootPageIds.indexOf(a.id);
      final idxB = _recentlyOpenedRootPageIds.indexOf(b.id);
      if (idxA == -1 && idxB == -1) return 0;
      if (idxA == -1) return 1;
      if (idxB == -1) return -1;
      return idxA.compareTo(idxB);
    });

    return PopScope(
      canPop: _navigationHistory.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _navigationHistory.isNotEmpty) {
          _goBack();
        }
      },
      child: Scaffold(
      appBar: AppBar(
        leading: (_selectedPage != null && _navigationHistory.isNotEmpty)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: _goBack,
              )
            : null,
        title: _buildAppBarTitle(),
        backgroundColor: const Color(0xFF191919),
        elevation: 0,
        actions: [
          if (_selectedPage != null) ...[
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
            IconButton(
              icon: _isRefreshingPage
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              tooltip: 'Refresh Page',
              onPressed: _isRefreshingPage ? null : _refreshSelectedPage,
            ),
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.view_sidebar_outlined),
                tooltip: 'Context Pages',
                onPressed: () {
                  Scaffold.of(context).openEndDrawer();
                },
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'delete') {
                  _archiveSelectedPage(_selectedPage!.id);
                } else if (value == 'subpage') {
                  _createSubpage(_selectedPage!.id);
                } else if (value == 'sidepage') {
                  _createSubpage(_selectedPage!.id, relationType: 'sidepage');
                } else if (value == 'move') {
                  _showMoveDialog();
                } else if (value == 'close') {
                  setState(() {
                    _selectedPage = null;
                    _navigationHistory.clear();
                  });
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'subpage',
                  child: Row(
                    children: [
                      Icon(Icons.add_box_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('Create Subpage'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'sidepage',
                  child: Row(
                    children: [
                      const Icon(Icons.open_in_new, size: 18),
                      const SizedBox(width: 8),
                      const Text('Create Side Page'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'move',
                  child: Row(
                    children: [
                      Icon(Icons.drive_file_move_outline, size: 18),
                      SizedBox(width: 8),
                      Text('Move To...'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.archive, size: 18, color: Colors.orangeAccent),
                      SizedBox(width: 8),
                      Text(
                        'Archive Page',
                        style: TextStyle(color: Colors.orangeAccent),
                      ),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'close',
                  child: Row(
                    children: [
                      Icon(Icons.close, size: 18),
                      SizedBox(width: 8),
                      Text('Close Note'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      drawer: _buildDrawer(rootPages, allPages),
      endDrawer: _selectedPage != null ? _buildSubpagesEndDrawer() : null,
      body: _selectedPage == null
          ? _buildDashboard(rootPages)
          : _buildPageEditor(),
      ),
    );
  }

  Widget _buildDrawer(List<DbPage> rootPages, List<DbPage> allPages) {
    final filteredRootPages = rootPages.where((p) {
      if (_sidebarSearchQuery.isEmpty) return true;
      return p.title.toLowerCase().contains(_sidebarSearchQuery.toLowerCase());
    }).toList();

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildDrawerHeader(),
            if (!_showArchived)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  onChanged: (val) {
                    setState(() {
                      _sidebarSearchQuery = val;
                    });
                  },
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Search root pages...',
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
                    prefixIcon: Icon(Icons.search, size: 14, color: Colors.grey),
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: _showArchived
                    ? (_archivedPages
                          .map((page) => _buildArchivedPageTile(page))
                          .toList())
                    : filteredRootPages
                          .map((page) => _buildPageTile(page))
                          .toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ElevatedButton.icon(
                onPressed: () => _createSubpage(null),
                icon: const Icon(Icons.add),
                label: const Text('Add Root Page'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF818CF8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        if (!_showArchived) {
                          final archived = await _serverService.getArchivedPages();
                          setState(() {
                            _archivedPages = archived;
                            _showArchived = true;
                          });
                        } else {
                          setState(() {
                            _showArchived = false;
                          });
                        }
                      },
                      icon: Icon(
                        _showArchived ? Icons.list_alt : Icons.archive_outlined,
                        size: 16,
                      ),
                      label: Text(_showArchived ? 'Active' : 'Trash'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey,
                        side: const BorderSide(color: Color(0xFF2C2C2C)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context); // Close drawer
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => SettingsScreen(serverService: _serverService),
                          ),
                        ).then((_) {
                          setState(() {});
                        });
                      },
                      icon: const Icon(Icons.settings_outlined, size: 16),
                      label: const Text('Settings'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey,
                        side: const BorderSide(color: Color(0xFF2C2C2C)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildSubpagesEndDrawer() {
    if (_selectedPage == null) return const SizedBox();

    return Drawer(
      width: 240,
      backgroundColor: const Color(0xFF161616),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF2C2C2C))),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Context',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF64748B),
                      letterSpacing: 0.5,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _sidePages.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Text(
                          'No context pages yet.\n\nSide pages provide supplementary info about the current page.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF4A4A4A),
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        vertical: 6,
                        horizontal: 8,
                      ),
                      itemCount: _sidePages.length,
                      itemBuilder: (context, idx) {
                        final sp = _sidePages[idx];
                        return Card(
                          color: const Color(0xFF1E1E1E),
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                            side: const BorderSide(color: Color(0xFF2E2E2E)),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: PageIcon(
                              emoji: sp.emoji,
                              size: 16,
                              dbService: _serverService.dbService,
                            ),
                            title: Text(
                              sp.title.isEmpty ? 'Untitled' : sp.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: Color(0xFF64748B),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              _selectPage(sp);
                            },
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _createSubpage(_selectedPage!.id, relationType: 'sidepage');
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text(
                  'Add Context Page',
                  style: TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF818CF8),
                  side: const BorderSide(color: Color(0xFF3E3E3E)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerHeader() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2C2C2C))),
      ),
      child: Column(
        children: [
          // Mode tabs
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (_isClientModeTab) {
                      setState(() => _isClientModeTab = false);
                      _serverService.exitClientMode();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _isClientModeTab
                              ? Colors.transparent
                              : const Color(0xFF818CF8),
                          width: 2,
                        ),
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'Host',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFCBD5E1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    if (!_isClientModeTab) {
                      setState(() => _isClientModeTab = true);
                      _serverService.enterClientMode();
                      _serverService.startDiscovery();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: _isClientModeTab
                              ? const Color(0xFF818CF8)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'Remote',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFCBD5E1),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          // Tab content
          if (_isClientModeTab)
            _buildRemoteModePanel()
          else
            _buildHostModePanel(),
        ],
      ),
    );
  }

  Widget _buildHostModePanel() {
    final isRunning = _serverService.isRunning;
    final clientsCount = _serverService.clients.length;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Cero Sync Hub',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Local Database Truth',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              Switch.adaptive(
                value: isRunning,
                activeColor: const Color(0xFF818CF8),
                onChanged: (val) async {
                  if (val) {
                    await _serverService.startServer();
                  } else {
                    await _serverService.stopServer();
                  }
                  setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF191919),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Server IP:',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      _serverService.localIp,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Port:',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      '${_serverService.wsPort}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Auth PIN:',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      _serverService.authPin.isEmpty
                          ? '—'
                          : _serverService.authPin,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF818CF8),
                        letterSpacing: 2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Connections:',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      '$clientsCount active',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_serverService.pendingConnections.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Pending Pairings:',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            ...List.generate(_serverService.pendingConnections.length, (i) {
              final p = _serverService.pendingConnections[i];
              return Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.remoteAddress,
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _serverService.approvePendingClient(i),
                      child: const Text('Allow', style: TextStyle(fontSize: 11, color: Colors.green)),
                    ),
                    TextButton(
                      onPressed: () => _serverService.rejectPendingClient(i),
                      child: const Text('Deny', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildRemoteModePanel() {
    final isConnected = _serverService.isClientConnected;
    final isPaired = _serverService.isClientPaired;
    final discoveredServers = _serverService.discoveredServers;
    final clientError = _serverService.clientError;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Remote Connection',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Connect to a Cero host',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          // Auto-connect Toggle Switch
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Auto-detect & connect',
                style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
              ),
              Switch.adaptive(
                value: _serverService.autoConnectEnabled,
                activeColor: const Color(0xFF818CF8),
                onChanged: (val) {
                  _serverService.setAutoConnect(val);
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Discovered servers
          if (!isConnected && discoveredServers.isNotEmpty) ...[
            const Text(
              'Discovered Hosts:',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 120,
              child: ListView(
                children: discoveredServers.map((server) {
                  return Card(
                    color: const Color(0xFF191919),
                    margin: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      title: Text(
                        server.deviceName,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        server.ip,
                        style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.grey),
                      ),
                      trailing: const Icon(Icons.link, size: 14, color: Color(0xFF818CF8)),
                      onTap: () {
                        _clientIpController.text = server.ip;
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const Divider(height: 16, color: Color(0xFF2C2C2C)),
          ],
          // Connection form
          if (!isConnected) ...[
            if (discoveredServers.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    'No hosts found. Scanning network for hosts...',
                    style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _clientIpController,
              style: const TextStyle(fontSize: 12, color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Host IP address',
                hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                filled: true,
                fillColor: Color(0xFF191919),
                border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3E3E3E))),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3E3E3E))),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF818CF8))),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _clientPinController,
                    style: const TextStyle(fontSize: 12, color: Colors.white, letterSpacing: 2),
                    decoration: const InputDecoration(
                      hintText: 'PIN',
                      hintStyle: TextStyle(fontSize: 12, color: Colors.grey),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      filled: true,
                      fillColor: Color(0xFF191919),
                      border: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3E3E3E))),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF3E3E3E))),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFF818CF8))),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  child: ElevatedButton(
                    onPressed: () async {
                      final ip = _clientIpController.text.trim();
                      final pin = _clientPinController.text.trim();
                      if (ip.isEmpty || pin.isEmpty) return;
                      await _serverService.connectToHost(ip, _serverService.wsPort, pin);
                      setState(() {});
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF818CF8),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: const Text('Connect', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
          // Connection status
          if (isConnected) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF191919),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        isPaired ? Icons.check_circle : Icons.hourglass_empty,
                        size: 14,
                        color: isPaired ? Colors.green : Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isPaired ? 'Connected & Paired' : 'Waiting for host approval...',
                        style: TextStyle(
                          fontSize: 11,
                          color: isPaired ? Colors.green : Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () async {
                        await _serverService.disconnectFromHost();
                        setState(() {});
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: const Text('Disconnect', style: TextStyle(fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (clientError.isNotEmpty && !isConnected) ...[
            const SizedBox(height: 8),
            Text(
              clientError,
              style: const TextStyle(fontSize: 10, color: Colors.redAccent),
            ),
          ],
        ],
      ),
    );
  }

  // Simplified flat representation of top-level root pages
  Widget _buildPageTile(DbPage page) {
    final isSelected = _selectedPage?.id == page.id;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF818CF8).withOpacity(0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        leading: PageIcon(
          emoji: page.emoji, 
          size: 15, 
          dbService: _serverService.dbService
        ),
        title: Text(
          page.title.isEmpty ? 'Untitled' : page.title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? const Color(0xFF818CF8)
                : const Color(0xFFCBD5E1),
          ),
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.add, size: 14, color: Color(0xFF64748B)),
          tooltip: 'Add subpage',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => _createSubpage(page.id),
        ),
        onTap: () {
          Navigator.pop(context);
          _selectPage(page);
        },
      ),
    );
  }

  Widget _buildArchivedPageTile(DbPage page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Card(
        color: const Color(0xFF191919),
        margin: EdgeInsets.zero,
        child: ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: PageIcon(emoji: page.emoji, size: 16, dbService: _serverService.dbService),
          title: Text(
            page.title.isEmpty ? 'Untitled' : page.title,
            style: const TextStyle(
              fontSize: 13,
              decoration: TextDecoration.lineThrough,
              color: Colors.grey,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.restore_outlined,
                  size: 18,
                  color: Colors.green,
                ),
                tooltip: 'Restore',
                onPressed: () async {
                  await _serverService.restorePage(page.id);
                  final archived = await _serverService.getArchivedPages();
                  setState(() {
                    _archivedPages = archived;
                  });
                },
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_forever_outlined,
                  size: 18,
                  color: Colors.redAccent,
                ),
                tooltip: 'Delete permanently',
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF202020),
                      title: const Text('Permanently Delete?'),
                      content: const Text('This action cannot be undone.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Delete Forever'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await _serverService.hardDeletePage(page.id);
                    final archived = await _serverService.getArchivedPages();
                    setState(() {
                      _archivedPages = archived;
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboard(List<DbPage> rootPages) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: CeroLogo(size: 80)),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Cero Personal Journal',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text(
                'Offline-first markdown notes, synced directly to your devices.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
            const SizedBox(height: 32),
            if (rootPages.isEmpty) ...[
              const Center(
                child: Text(
                  'No journal entries created yet.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _createSubpage(null),
                icon: const Icon(Icons.add),
                label: const Text('Create First Page'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF818CF8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ] else ...[
              const Text(
                'Recent Notes',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 10),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: rootPages.take(4).length,
                itemBuilder: (context, idx) {
                  final page = rootPages[idx];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      leading: PageIcon(
                        emoji: page.emoji,
                        size: 20,
                        dbService: _serverService.dbService,
                      ),
                      title: Text(
                        page.title.isEmpty ? 'Untitled' : page.title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        page.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      onTap: () => _selectPage(page),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
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
                    // DOCK LAYOUT SWITCHER
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
                            _scratchpadController.text,
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

  Widget _buildPageEditor() {
    if (_selectedPage == null) return const SizedBox();

    Widget mainEditor = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Focus(autofocus: true, child: SizedBox.shrink()),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            children: [
              GestureDetector(
                onTap: _showEmojiPicker,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: PageIcon(
                    emoji: _selectedPage!.emoji,
                    size: 32,
                    dbService: _serverService.dbService,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _titleController,
                  focusNode: _titleFocusNode,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Untitled',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.grey),
                  ),
                  onChanged: (val) => _saveCurrentPage(),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: CardColumn(
            cards: _pageCards,
            allPages: _serverService.pages,
            selectedPage: _selectedPage!,
            scrollController: _cardScrollController,
            dbService: _serverService.dbService,
            serverService: _serverService,
            onNavigateToPage: _selectPage,
            onCardUpdated: (cardId, content) async {
              await _serverService.updateCard(id: cardId, content: content);
              _loadCardsForPage(_selectedPage!.id);
            },
            onCardAdded: (pageId, type, content, {insertAt}) async {
              final newCard = await _serverService.addCard(
                pageId: pageId,
                type: type,
                content: content,
                insertAt: insertAt,
              );
              _loadCardsForPage(pageId);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_cardScrollController.hasClients) {
                  _cardScrollController.jumpTo(
                    _cardScrollController.position.maxScrollExtent,
                  );
                }
              });
              return newCard;
            },
            onCardDeleted: (cardId) async {
              await _serverService.deleteCard(cardId);
              _loadCardsForPage(_selectedPage!.id);
            },
            onCardsReordered: (cardIds) async {
              await _serverService.reorderCards(cardIds: cardIds);
              _loadCardsForPage(_selectedPage!.id);
            },
            onCreateNewPage: (parentId) async {
              return await _createSubpage(parentId);
            },
          ),
        ),
      ],
    );

    final bool showSplitPane = _showScratchpad || _showTally;
    final Widget splitPaneWidget = _showScratchpad ? _buildScratchpadPane() : _buildTallyPane();

    if (showSplitPane) {
      if (_scratchpadHorizontalLayout) {
        return Row(
          children: [
            Expanded(child: mainEditor),
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
        return Column(
          children: [
            Expanded(child: mainEditor),
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
    }

    return mainEditor;
  }
}
