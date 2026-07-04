import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'services/server_service.dart';
import 'models/page_model.dart';
import 'models/card_model.dart' as models;

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
        scaffoldBackgroundColor: const Color(0xFF191919), // Notion Dark
        primaryColor: const Color(0xFF818CF8), // Soft Violet
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF818CF8),
          brightness: Brightness.dark,
          primary: const Color(0xFF818CF8),
          secondary: const Color(0xFF818CF8),
          surface: const Color(0xFF202020),
          background: const Color(0xFF191919),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF202020),
          elevation: 0,
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: Color(0xFF202020),
        ),
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
  
  // Selected page state
  DbPage? _selectedPage;
  bool _isEditing = false; // Toggle between Edit and Preview

  // Navigation State
  final Set<String> _expandedPageIds = {};
  bool _showArchived = false;
  List<DbPage> _archivedPages = [];
  final List<String> _navigationHistory = []; // Stack for Back functionality

  // Text Editing Controllers
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _contentController = TextEditingController();
  final FocusNode _contentFocusNode = FocusNode();
  final FocusNode _titleFocusNode = FocusNode();

  // Card state for current page
  List<models.Card> _currentCards = [];
  models.Card? _activeCard; // The markdown card being edited

  // Debounce timer for save operations
  Timer? _saveDebounceTimer;

  final List<String> _curatedEmojis = [
    '📓', '📝', '📅', '💭', '💡', '🏷️', '✈️', '🏃', '💻', '🏠', 
    '🎨', '🎵', '📚', '✍️', '❤️', '🌟', '🍀', '☀️', '🌧️', '☕', 
    '🧠', '🔋', '🏡', '🎯'
  ];

  @override
  void initState() {
    super.initState();
    _serverService = widget.serverService;
    _serverService.addListener(_onServerStateChanged);
  }

  @override
  void dispose() {
    _serverService.removeListener(_onServerStateChanged);
    _titleController.dispose();
    _contentController.dispose();
    _contentFocusNode.dispose();
    _titleFocusNode.dispose();
    _saveDebounceTimer?.cancel();
    super.dispose();
  }

  void _onServerStateChanged() {
    if (mounted) {
      setState(() {
        if (_selectedPage != null) {
          final updatedPage = _serverService.pages.firstWhere(
            (p) => p.id == _selectedPage!.id,
            orElse: () => _selectedPage!,
          );

          if (!_serverService.pages.any((p) => p.id == _selectedPage!.id)) {
            _selectedPage = null;
            _isEditing = false;
            _navigationHistory.clear();
            _currentCards = [];
            _activeCard = null;
          } else if (updatedPage.revision > _selectedPage!.revision) {
            _selectedPage = updatedPage;
            if (!_contentFocusNode.hasFocus && !_titleFocusNode.hasFocus) {
              _titleController.text = updatedPage.title;
              _loadCardsForPage(updatedPage.id);
            }
          }
        }

        _checkPendingConnections();
      });
    }
  }

  Future<void> _loadCardsForPage(String pageId) async {
    try {
      final cards = await _serverService.dbService.getCards(pageId);
      setState(() {
        _currentCards = cards;
        _activeCard = cards.isNotEmpty
            ? cards.firstWhere(
                (c) => c.type == 'markdown',
                orElse: () => cards.first,
              )
            : null;
        if (_activeCard != null) {
          _contentController.text = _activeCard!.content;
        } else {
          _contentController.text = '';
        }
      });
    } catch (e) {
      debugPrint('Error loading cards: $e');
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
            child: const Text('Deny', style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            onPressed: () {
              _serverService.approvePendingClient(index);
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF818CF8)),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
  }

  void _selectPage(DbPage page, {bool pushToHistory = true}) {
    _flushPendingSave();

    if (pushToHistory && _selectedPage != null && _selectedPage!.id != page.id) {
      _navigationHistory.add(_selectedPage!.id);
    }
    setState(() {
      _selectedPage = page;
      _titleController.text = page.title;
      _isEditing = false;
      _currentCards = [];
      _activeCard = null;
    });
    _loadCardsForPage(page.id);
  }

  void _goBack() {
    while (_navigationHistory.isNotEmpty) {
      final prevId = _navigationHistory.removeLast();
      // Check if page still exists and is not archived
      final exists = _serverService.pages.any((p) => p.id == prevId);
      if (exists) {
        final prevPage = _serverService.pages.firstWhere((p) => p.id == prevId);
        _selectPage(prevPage, pushToHistory: false);
        return;
      }
    }
  }

  void _flushPendingSave() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    if (_selectedPage == null) return;

    final newTitle = _titleController.text.trim().isEmpty
        ? 'Untitled'
        : _titleController.text.trim();

    // Save page title/emoji
    _serverService.updatePage(
      id: _selectedPage!.id,
      title: newTitle,
      emoji: _selectedPage!.emoji,
    );

    // Save active card content
    if (_activeCard != null) {
      _serverService.updateCard(
        id: _activeCard!.id,
        content: _contentController.text,
      );
    }
  }

  void _saveCurrentPage() {
    if (_selectedPage == null) return;
    
    // Debounce: cancel any pending save and restart timer
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      _flushPendingSave();
    });
  }

  void _saveCurrentPageImmediate() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    _flushPendingSave();
  }

  void _createSubpage(String? parentId, {String relationType = 'subpage'}) async {
    await _serverService.addPage(
      parentId: parentId,
      relationType: relationType,
      title: 'New Page',
      emoji: '📝',
    );

    // Create the first markdown card for the new page
    final newPage = _serverService.pages.last;
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
                  _isEditing = false;
                  _navigationHistory.clear();
                });
              }
              await _serverService.deletePage(id);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
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
                leading: const Icon(Icons.folder_off_outlined, color: Colors.grey),
                title: const Text('Root Level (No Parent)', style: TextStyle(fontSize: 13)),
                onTap: () => Navigator.pop(ctx, ''),
              ),
              ...allPages
                .where((p) => p.id != currentPage.id)
                .map((page) => ListTile(
                  dense: true,
                  leading: Text(page.emoji, style: const TextStyle(fontSize: 16)),
                  title: Text(page.title.isEmpty ? 'Untitled' : page.title, style: const TextStyle(fontSize: 13)),
                  subtitle: page.parentId != null ? const Text('subpage', style: TextStyle(fontSize: 10, color: Colors.grey)) : null,
                  onTap: () => Navigator.pop(ctx, page.id),
                )),
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
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF202020),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Select Emoji Icon',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              itemCount: _curatedEmojis.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemBuilder: (context, index) {
                final emoji = _curatedEmojis[index];
                return InkWell(
                  onTap: () {
                    setState(() {
                      _selectedPage = _selectedPage!.copyWith(emoji: emoji);
                    });
                    _saveCurrentPageImmediate();
                    Navigator.pop(context);
                  },
                  child: Center(
                    child: Text(
                      emoji,
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Helper to insert markdown tags at cursor position
  void _insertMarkdown(String prefix, String suffix) {
    final text = _contentController.text;
    final selection = _contentController.selection;
    
    if (!selection.isValid) return;

    final selectedText = selection.textInside(text);
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      '$prefix$selectedText$suffix',
    );
    
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + prefix.length + selectedText.length,
      ),
    );
    _saveCurrentPageImmediate();
  }

  @override
  Widget build(BuildContext context) {
    final allPages = _serverService.pages;
    final rootPages = allPages.where((p) => p.parentId == null).toList();

    return Scaffold(
      appBar: AppBar(
        leading: (_selectedPage != null && _navigationHistory.isNotEmpty)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: _goBack,
              )
            : null,
        title: Row(
          children: [
            const Text(
              'Cero',
              style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: -0.5),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _serverService.isRunning 
                    ? Colors.green.withOpacity(0.1) 
                    : Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _serverService.isRunning ? 'LINK ON' : 'LINK OFF',
                style: TextStyle(
                  fontSize: 10, 
                  fontWeight: FontWeight.bold,
                  color: _serverService.isRunning ? Colors.green : Colors.grey,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF191919),
        elevation: 0,
        actions: [
          if (_selectedPage != null) ...[
            // Button to toggle the right subpages drawer
            Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.format_list_bulleted),
                tooltip: 'Subpages Sidebar',
                onPressed: () {
                  Scaffold.of(context).openEndDrawer();
                },
              ),
            ),
            // Toggle Edit vs Preview Mode
            IconButton(
              icon: Icon(_isEditing ? Icons.visibility : Icons.edit),
              tooltip: _isEditing ? 'Preview Mode' : 'Edit Mode',
              onPressed: () {
                if (_isEditing) {
                  _saveCurrentPageImmediate();
                }
                setState(() {
                  _isEditing = !_isEditing;
                });
              },
            ),
            // Options Dropdown
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'delete') {
                  _archiveSelectedPage(_selectedPage!.id);
                } else if (value == 'subpage') {
                  _createSubpage(_selectedPage!.id);
                } else if (value == 'move') {
                  _showMoveDialog();
                } else if (value == 'close') {
                  setState(() {
                    _selectedPage = null;
                    _isEditing = false;
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
                      Text('Archive Page', style: TextStyle(color: Colors.orangeAccent)),
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
            )
          ]
        ],
      ),
      drawer: _buildDrawer(rootPages, allPages),
      endDrawer: _selectedPage != null ? _buildSubpagesEndDrawer() : null,
      body: _selectedPage == null
          ? _buildDashboard(rootPages)
          : _buildPageEditor(),
    );
  }

  Widget _buildDrawer(List<DbPage> rootPages, List<DbPage> allPages) {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header with Sync Control
            _buildDrawerHeader(),
            
            // Nested Pages List (or Archived Pages)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: _showArchived
                    ? (_archivedPages.map((page) => _buildArchivedPageTile(page)).toList())
                    : rootPages.map((page) => _buildPageTreeNode(page, allPages, 0)).toList(),
              ),
            ),
            
            // Sidebar Footer Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: ElevatedButton.icon(
                onPressed: () => _createSubpage(null),
                icon: const Icon(Icons.add),
                label: const Text('Add Root Page'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF818CF8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 4, 16),
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
                icon: Icon(_showArchived ? Icons.list_alt : Icons.archive_outlined, size: 16),
                label: Text(_showArchived ? 'Show Active Pages' : 'View Trash'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey,
                  side: const BorderSide(color: Color(0xFF2C2C2C)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Right sidebar drawer showing a vertical list of subpages scrollable up to bottom
  Widget _buildSubpagesEndDrawer() {
    if (_selectedPage == null) return const SizedBox();

    final subpages = _serverService.pages
        .where((p) => p.parentId == _selectedPage!.id)
        .toList();

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFF2C2C2C)),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Subpages',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Inside: ${_selectedPage!.title.isEmpty ? 'Untitled' : _selectedPage!.title}',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: subpages.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: Text(
                          'No subpages inside this note.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      itemCount: subpages.length,
                      itemBuilder: (context, idx) {
                        final subpage = subpages[idx];
                        return Card(
                          color: const Color(0xFF191919),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: Text(subpage.emoji, style: const TextStyle(fontSize: 18)),
                            title: Text(
                              subpage.title.isEmpty ? 'Untitled' : subpage.title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () {
                              Navigator.pop(context); // Close Drawer
                              _selectPage(subpage);
                            },
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(context); // Close Drawer
                  _createSubpage(_selectedPage!.id);
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Subpage'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF818CF8),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerHeader() {
    final isRunning = _serverService.isRunning;
    final clientsCount = _serverService.clients.length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF2C2C2C)),
        ),
      ),
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
                    const Text('Server IP:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(
                      _serverService.localIp,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Port:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text('${_serverService.wsPort}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Auth PIN:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(
                      _serverService.authPin.isEmpty ? '—' : _serverService.authPin,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF818CF8), letterSpacing: 2),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Connections:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text('$clientsCount active', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageTreeNode(DbPage page, List<DbPage> allPages, int depth) {
    final children = allPages.where((p) => p.parentId == page.id).toList();
    final hasChildren = children.isNotEmpty;
    final isExpanded = _expandedPageIds.contains(page.id);
    final isSelected = _selectedPage?.id == page.id;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.only(left: depth * 14.0),
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        _expandedPageIds.remove(page.id);
                      } else {
                        _expandedPageIds.add(page.id);
                      }
                    });
                  },
                  child: Icon(
                    hasChildren 
                        ? (isExpanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right) 
                        : Icons.circle,
                    size: hasChildren ? 18 : 6,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(width: 8),
                Text(page.emoji, style: const TextStyle(fontSize: 16)),
              ],
            ),
            title: Text(
              page.title.isEmpty ? 'Untitled' : page.title,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? const Color(0xFF818CF8) : Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.add, size: 16),
              tooltip: 'Add subpage',
              onPressed: () => _createSubpage(page.id),
            ),
            onTap: () {
              Navigator.pop(context); // Close Drawer
              _selectPage(page);
            },
          ),
        ),
        if (hasChildren && isExpanded)
          ...children.map((child) => _buildPageTreeNode(child, allPages, depth + 1)).toList(),
      ],
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
          leading: Text(page.emoji, style: const TextStyle(fontSize: 16)),
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
                icon: const Icon(Icons.restore_outlined, size: 18, color: Colors.green),
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
                icon: const Icon(Icons.delete_forever_outlined, size: 18, color: Colors.redAccent),
                tooltip: 'Delete permanently',
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: const Color(0xFF202020),
                      title: const Text('Permanently Delete?'),
                      content: const Text('This action cannot be undone.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
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
            const Center(
              child: Text(
                '📓',
                style: TextStyle(fontSize: 72),
              ),
            ),
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
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ] else ...[
              const Text(
                'Recent Notes',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey),
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
                      leading: Text(page.emoji, style: const TextStyle(fontSize: 20)),
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

  Widget _buildPageEditor() {
    if (_selectedPage == null) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Helper Toolbar for Markdown editing (Only in Edit mode)
        if (_isEditing) _buildMarkdownToolbar(),
        
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Page Emoji Header
                GestureDetector(
                  onTap: _showEmojiPicker,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _selectedPage!.emoji,
                      style: const TextStyle(fontSize: 48),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                
                // Page Title Field
                TextField(
                  controller: _titleController,
                  focusNode: _titleFocusNode,
                  enabled: _isEditing,
                  style: const TextStyle(
                    fontSize: 26, 
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Untitled',
                    border: InputBorder.none,
                    hintStyle: TextStyle(color: Colors.grey),
                  ),
                  onChanged: (val) => _saveCurrentPage(),
                ),
                const SizedBox(height: 16),
                
                // Content Body (Edit area vs Rendered Markdown Preview)
                _isEditing
                    ? TextField(
                        controller: _contentController,
                        focusNode: _contentFocusNode,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        style: const TextStyle(fontSize: 15, height: 1.5, fontFamily: 'monospace'),
                        decoration: const InputDecoration(
                          hintText: 'Start writing notes...',
                          border: InputBorder.none,
                        ),
                        onChanged: (val) => _saveCurrentPage(),
                      )
                    : MarkdownBody(
                        data: _contentController.text,
                        selectable: true,
                        styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                          p: const TextStyle(fontSize: 15, height: 1.6, color: Color(0xFFE2E8F0)),
                          h1: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, height: 1.8),
                          h2: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, height: 1.8),
                          h3: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, height: 1.8),
                          code: const TextStyle(fontFamily: 'monospace', backgroundColor: Color(0xFF2C2C2C)),
                        ),
                      ),
                

              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMarkdownToolbar() {
    return Container(
      color: const Color(0xFF202020),
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          IconButton(
            icon: const Icon(Icons.format_bold, size: 18),
            tooltip: 'Bold',
            onPressed: () => _insertMarkdown('**', '**'),
          ),
          IconButton(
            icon: const Icon(Icons.format_italic, size: 18),
            tooltip: 'Italic',
            onPressed: () => _insertMarkdown('*', '*'),
          ),
          IconButton(
            icon: const Icon(Icons.title, size: 18),
            tooltip: 'Heading 1',
            onPressed: () => _insertMarkdown('# ', ''),
          ),
          IconButton(
            icon: const Icon(Icons.format_list_bulleted, size: 18),
            tooltip: 'Bullet List',
            onPressed: () => _insertMarkdown('- ', ''),
          ),
          IconButton(
            icon: const Icon(Icons.check_box_outlined, size: 18),
            tooltip: 'Checkbox',
            onPressed: () => _insertMarkdown('- [ ] ', ''),
          ),
          IconButton(
            icon: const Icon(Icons.code, size: 18),
            tooltip: 'Code Block',
            onPressed: () => _insertMarkdown('```\n', '\n```'),
          ),
        ],
      ),
    );
  }
}
