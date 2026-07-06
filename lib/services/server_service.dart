import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/page_model.dart';
import '../models/card_model.dart';
import 'database_service.dart';

class ClientConnection {
  final WebSocket socket;
  final String remoteAddress;
  bool approved;
  ClientConnection(this.socket, this.remoteAddress, {this.approved = false});
}

class PendingConnection {
  final WebSocket socket;
  final String remoteAddress;
  final Completer<bool> completer;
  PendingConnection(this.socket, this.remoteAddress, this.completer);
}

class ServerService extends ChangeNotifier {
  final DatabaseService _dbService = DatabaseService();
  HttpServer? _httpServer;
  RawDatagramSocket? _udpSocket;
  Timer? _udpBroadcastTimer;

  bool _isRunning = false;
  String _localIp = 'Unknown';
  final int _wsPort = 9090;
  final int _udpPort = 9100;
  static const String _multicastAddr = '239.255.255.250';

  String _authPin = '';
  String get authPin => _authPin;

  final List<ClientConnection> _clients = [];
  final List<PendingConnection> _pendingConnections = [];
  List<DbPage> _pages = [];

  bool get isRunning => _isRunning;
  String get localIp => _localIp;
  int get wsPort => _wsPort;
  List<ClientConnection> get clients => _clients;
  List<PendingConnection> get pendingConnections => _pendingConnections;
  List<DbPage> get pages => _pages;
  DatabaseService get dbService => _dbService;

  // --- Initialization ---

  Future<void> init() async {
    await _dbService.openDefaultWorkspace();
    await updateLocalIp();
    await loadDatabaseState();
  }

  Future<void> loadDatabaseState() async {
    try {
      _pages = await _dbService.getAllPages();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading pages from SQLite: $e');
    }
  }

  Future<void> updateLocalIp() async {
    try {
      List<NetworkInterface> interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      if (interfaces.isNotEmpty) {
        for (var interface in interfaces) {
          for (var addr in interface.addresses) {
            if (!addr.isLoopback) {
              _localIp = addr.address;
              notifyListeners();
              return;
            }
          }
        }
        _localIp = interfaces.first.addresses.first.address;
      } else {
        _localIp = '127.0.0.1';
      }
    } catch (e) {
      _localIp = '127.0.0.1';
      debugPrint('Error getting local IP: $e');
    }
    notifyListeners();
  }

  // --- Workspace Management ---

  Future<void> switchWorkspace(String filePath) async {
    await _dbService.switchWorkspace(filePath);
    await loadDatabaseState();
    final paths = await _dbService.listWorkspaces();
    final names = paths.map((p) {
      final filename = p.split(Platform.pathSeparator).last;
      return filename.replaceAll('.db', '');
    }).toList();
    _broadcastToAllClients({
      'type': 'workspace_status',
      'activeWorkspace': _dbService.currentWorkspaceName,
      'availableWorkspaces': names,
    });
    _broadcastMetadataToAllClients();
    notifyListeners();
  }

  Future<List<String>> listWorkspaces() async {
    return await _dbService.listWorkspaces();
  }

  // --- Server Lifecycle ---

  Future<bool> startServer() async {
    if (_isRunning) return true;

    try {
      await updateLocalIp();
      await loadDatabaseState();

      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, _wsPort);
      debugPrint('Cero Sync Server listening on $_localIp:$_wsPort');

      _httpServer!.listen((HttpRequest request) {
        if (request.uri.path == '/ws') {
          final pin = request.uri.queryParameters['pin'] ?? '';
          if (pin != _authPin) {
            request.response
              ..statusCode = HttpStatus.forbidden
              ..write('Invalid auth PIN')
              ..close();
            debugPrint('Rejected connection: invalid PIN ($pin)');
            return;
          }

          final remoteAddress = request.connectionInfo?.remoteAddress.address ?? 'Unknown';
          WebSocketTransformer.upgrade(request).then((WebSocket socket) {
            _handleNewClient(socket, remoteAddress);
          }).catchError((e) {
            debugPrint('Error upgrading to WebSocket: $e');
          });
        } else {
          request.response
            ..statusCode = HttpStatus.notFound
            ..write('Not Found')
            ..close();
        }
      });

      _authPin = _generatePin();

      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.joinMulticast(InternetAddress(_multicastAddr));
      debugPrint('UDP Multicast socket bound on $_multicastAddr');

      _udpBroadcastTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
        _broadcastDiscoveryBeacon();
      });

      _isRunning = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Failed to start server: $e');
      stopServer();
      return false;
    }
  }

  Future<void> stopServer() async {
    _udpBroadcastTimer?.cancel();
    _udpBroadcastTimer = null;

    _udpSocket?.close();
    _udpSocket = null;

    for (var client in _clients) {
      try {
        client.socket.close(WebSocketStatus.goingAway, 'Server stopping');
      } catch (e) {
        debugPrint('Error closing client socket: $e');
      }
    }
    _clients.clear();

    await _httpServer?.close(force: true);
    _httpServer = null;

    _isRunning = false;
    notifyListeners();
  }

  // --- UDP Discovery ---

  void _broadcastDiscoveryBeacon() {
    if (_udpSocket == null) return;

    try {
      final beaconData = {
        'app': 'cero-journal',
        'port': _wsPort,
        'ip': _localIp,
        'deviceName': Platform.isAndroid
            ? 'Android Phone'
            : Platform.isIOS
                ? 'iPhone'
                : 'Cero Mobile Server (${Platform.operatingSystem})',
      };

      final String payload = jsonEncode(beaconData);
      final List<int> dataToSend = utf8.encode(payload);

      _udpSocket!.send(dataToSend, InternetAddress(_multicastAddr), _udpPort);
      _udpSocket!.send(dataToSend, InternetAddress('255.255.255.255'), _udpPort);
    } catch (e) {
      debugPrint('UDP broadcast error: $e');
    }
  }

  // --- WebSocket Client Handling ---

  void _handleNewClient(WebSocket socket, String remoteAddress) {
    debugPrint('New connection from $remoteAddress');

    final pairMsg = {
      'type': 'pairing_required',
      'remoteAddress': remoteAddress,
    };
    socket.add(jsonEncode(pairMsg));

    final completer = Completer<bool>();
    final pending = PendingConnection(socket, remoteAddress, completer);
    _pendingConnections.add(pending);
    notifyListeners();
    debugPrint('Pending pairing from: $remoteAddress');

    socket.listen(
      (message) {
        if (pending.completer.isCompleted) {
          _handleIncomingMessage(socket, message);
        } else {
          debugPrint('Ignoring message from unapproved client: $remoteAddress');
        }
      },
      onDone: () {
        _pendingConnections.remove(pending);
        _clients.removeWhere((c) => c.socket == socket);
        notifyListeners();
        debugPrint('Desktop disconnected: $remoteAddress');
      },
      onError: (error) {
        _pendingConnections.remove(pending);
        _clients.removeWhere((c) => c.socket == socket);
        notifyListeners();
        debugPrint('Desktop client socket error: $error ($remoteAddress)');
      },
    );

    completer.future.then((approved) {
      _pendingConnections.remove(pending);
      _handleApprovedClient(socket, remoteAddress, approved);
    });
  }

  void _handleApprovedClient(WebSocket socket, String remoteAddress, bool approved) {
    if (!approved) {
      try {
        final rejectMsg = {'type': 'pairing_rejected'};
        socket.add(jsonEncode(rejectMsg));
        socket.close(4002, 'Pairing rejected by user');
      } catch (_) {}
      notifyListeners();
      debugPrint('Pairing rejected: $remoteAddress');
      return;
    }

    final clientConnection = ClientConnection(socket, remoteAddress, approved: true);
    _clients.add(clientConnection);
    notifyListeners();
    debugPrint('Desktop connected (approved): $remoteAddress');

    final acceptMsg = {'type': 'pairing_accepted'};
    socket.add(jsonEncode(acceptMsg));

    _sendWorkspaceStatus(socket);
    _syncMetadataToClient(socket);
  }

  Future<void> approvePendingClient(int index) async {
    if (index < 0 || index >= _pendingConnections.length) return;
    _pendingConnections[index].completer.complete(true);
  }

  Future<void> rejectPendingClient(int index) async {
    if (index < 0 || index >= _pendingConnections.length) return;
    _pendingConnections[index].completer.complete(false);
  }

  // --- Incoming Message Router ---

  void _handleIncomingMessage(WebSocket sender, dynamic message) async {
    if (message is! String) return;

    try {
      final data = jsonDecode(message);
      final String type = data['type'] ?? '';

      switch (type) {
        case 'add':
          if (data['item'] != null) {
            final newPage = DbPage.fromMap(data['item']);
            await _addItem(newPage, fromRemote: true);
          }
          break;
        case 'update':
          if (data['item'] != null) {
            final Map<String, dynamic> itemMap = Map<String, dynamic>.from(data['item']);
            final String pageId = itemMap['id'] ?? '';
            if (pageId.isNotEmpty) {
              final index = _pages.indexWhere((p) => p.id == pageId);
              if (index != -1) {
                final existingPage = _pages[index];
                final mergedMap = existingPage.toMap();
                itemMap.forEach((key, value) {
                  if (value != null) mergedMap[key] = value;
                });
                mergedMap['updated_at'] = DateTime.now().toIso8601String();
                final updatedPage = DbPage.fromMap(mergedMap);
                await _updateItem(updatedPage, fromRemote: true);
              }
            }
          }
          break;
        case 'delete':
        case 'archive':
          final String id = data['id'] ?? '';
          if (id.isNotEmpty) await _archiveItem(id, fromRemote: true);
          break;
        case 'restore':
          final String id = data['id'] ?? '';
          if (id.isNotEmpty) await _restoreItem(id, fromRemote: true);
          break;
        case 'move':
          final String moveId = data['id'] ?? '';
          final String newParentId = data['parent_id'] ?? '';
          if (moveId.isNotEmpty) {
            await _moveItem(moveId, newParentId.isEmpty ? null : newParentId, fromRemote: true);
          }
          break;
        case 'hard_delete':
          final String hardDeleteId = data['id'] ?? '';
          if (hardDeleteId.isNotEmpty) {
            await hardDeletePage(hardDeleteId);
          }
          break;

        case 'fetch_cards':
          final String pageId = data['page_id'] ?? '';
          if (pageId.isNotEmpty) await _sendCardsToClient(sender, pageId);
          break;
        case 'add_card':
          if (data['item'] != null) {
            final card = Card.fromMap(data['item']);
            await _addCard(card, fromRemote: true);
          }
          break;
        case 'update_card':
          if (data['item'] != null) {
            final Map<String, dynamic> itemMap = Map<String, dynamic>.from(data['item']);
            final String cardId = itemMap['id'] ?? '';
            if (cardId.isNotEmpty) {
              final existingCard = await _dbService.getCard(cardId);
              if (existingCard != null) {
                final mergedMap = existingCard.toMap();
                itemMap.forEach((key, value) {
                  if (value != null) mergedMap[key] = value;
                });
                mergedMap['updated_at'] = DateTime.now().toIso8601String();
                final card = Card.fromMap(mergedMap);
                await _updateCard(card, fromRemote: true);
              }
            }
          }
          break;
        case 'delete_card':
          final String cardId = data['id'] ?? '';
          final String deletePageId = data['page_id'] ?? '';
          if (cardId.isNotEmpty) {
            await _deleteCard(cardId, deletePageId: deletePageId, fromRemote: true);
          }
          break;
        case 'reorder_cards':
          final String pageId = data['page_id'] ?? '';
          final List<String> order = List<String>.from(data['order'] ?? []);
          if (pageId.isNotEmpty && order.isNotEmpty) {
            await _reorderCards(pageId, order, fromRemote: true);
          }
          break;

        case 'switch_workspace':
          final String wsName = data['workspaceName'] ?? '';
          if (wsName.isNotEmpty) await _handleSwitchWorkspace(wsName);
          break;
        case 'list_workspaces':
          await _handleListWorkspaces(sender);
          break;
        case 'create_workspace':
          final String newWsName = data['workspaceName'] ?? '';
          if (newWsName.isNotEmpty) await _handleCreateWorkspace(newWsName, sender);
          break;

        default:
          debugPrint('Unknown message type: $type');
      }
    } catch (e) {
      debugPrint('Error parsing client message: $e');
    }
  }

  // --- Helpers ---

  String _generatePin() {
    final random = Random.secure();
    return '${1000 + random.nextInt(9000)}';
  }

  static String generateId() {
    final random = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(16, (index) => chars[random.nextInt(chars.length)]).join();
  }

  void _broadcastToAllClients(Map<String, dynamic> messageMap) {
    final messageJson = jsonEncode(messageMap);
    for (var client in _clients) {
      try {
        client.socket.add(messageJson);
      } catch (e) {
        debugPrint('Error sending message to client: $e');
      }
    }
  }

  // --- Sync Methods ---

  void _sendWorkspaceStatus(WebSocket socket) async {
    try {
      final paths = await _dbService.listWorkspaces();
      final names = paths.map((p) {
        final filename = p.split(Platform.pathSeparator).last;
        return filename.replaceAll('.db', '');
      }).toList();
      final msg = {
        'type': 'workspace_status',
        'activeWorkspace': _dbService.currentWorkspaceName,
        'availableWorkspaces': names,
      };
      socket.add(jsonEncode(msg));
    } catch (e) {
      debugPrint('Error sending workspace status: $e');
    }
  }

  void _syncMetadataToClient(WebSocket socket) {
    try {
      final metaData = _pages.map((page) => {
        'id': page.id,
        'parent_id': page.parentId,
        'relation_type': page.relationType,
        'title': page.title,
        'emoji': page.emoji,
        'created_at': page.createdAt.toIso8601String(),
        'updated_at': page.updatedAt.toIso8601String(),
        'is_archived': page.isArchived ? 1 : 0,
        'sort_order': page.sortOrder,
        'revision': page.revision,
      }).toList();

      socket.add(jsonEncode({
        'type': 'sync',
        'data': metaData,
      }));
    } catch (e) {
      debugPrint('Error syncing metadata: $e');
    }
  }

  Future<void> _sendCardsToClient(WebSocket socket, String pageId) async {
    try {
      final cards = await _dbService.getCards(pageId);
      socket.add(jsonEncode({
        'type': 'sync_cards',
        'page_id': pageId,
        'cards': cards.map((c) => c.toMap()).toList(),
      }));
    } catch (e) {
      debugPrint('Error sending cards to client: $e');
    }
  }

  // --- Multiplayer State Synchronization Broadcasts ---

  void _broadcastMetadataToAllClients() {
    try {
      final metaData = _pages.map((page) => {
        'id': page.id,
        'parent_id': page.parentId,
        'relation_type': page.relationType,
        'title': page.title,
        'emoji': page.emoji,
        'created_at': page.createdAt.toIso8601String(),
        'updated_at': page.updatedAt.toIso8601String(),
        'is_archived': page.isArchived ? 1 : 0,
        'sort_order': page.sortOrder,
        'revision': page.revision,
      }).toList();

      _broadcastToAllClients({
        'type': 'sync',
        'data': metaData,
      });
    } catch (e) {
      debugPrint('Error broadcasting metadata state: $e');
    }
  }

  Future<void> _broadcastCardsToAllClients(String pageId) async {
    try {
      final cards = await _dbService.getCards(pageId);
      _broadcastToAllClients({
        'type': 'sync_cards',
        'page_id': pageId,
        'cards': cards.map((c) => c.toMap()).toList(),
      });
    } catch (e) {
      debugPrint('Error broadcasting card state for page $pageId: $e');
    }
  }

  // --- Page Action Handlers ---

  Future<DbPage> addPage({
    String? parentId,
    String relationType = 'subpage',
    required String title,
    required String emoji,
  }) async {
    final newPage = DbPage(
      id: generateId(),
      parentId: parentId,
      relationType: relationType,
      title: title,
      emoji: emoji,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _addItem(newPage, fromRemote: false);
    return newPage;
  }

  Future<void> _addItem(DbPage page, {required bool fromRemote}) async {
    if (_pages.any((p) => p.id == page.id)) return;

    try {
      await _dbService.insertPage(page);
      _pages.add(page);
      notifyListeners();

      _broadcastMetadataToAllClients();
    } catch (e) {
      debugPrint('Error inserting page: $e');
    }
  }

  Future<void> updatePage({
    required String id,
    required String title,
    required String emoji,
  }) async {
    final index = _pages.indexWhere((p) => p.id == id);
    if (index != -1) {
      final updatedPage = _pages[index].copyWith(
        title: title,
        emoji: emoji,
        updatedAt: DateTime.now(),
        revision: _pages[index].revision + 1,
      );
      await _updateItem(updatedPage, fromRemote: false);
    }
  }

  Future<void> _updateItem(DbPage page, {required bool fromRemote}) async {
    final index = _pages.indexWhere((p) => p.id == page.id);
    if (index != -1) {
      if (fromRemote &&
          page.revision > 0 &&
          page.revision < _pages[index].revision) {
        debugPrint('Rejected stale update for ${page.id}: local rev ${_pages[index].revision} > incoming rev ${page.revision}');
        return;
      }

      try {
        final updatedPage = page.copyWith(
          revision: fromRemote && page.revision > 0
              ? page.revision
              : _pages[index].revision + 1,
        );

        await _dbService.updatePage(updatedPage);
        _pages[index] = updatedPage;
        notifyListeners();

        _broadcastMetadataToAllClients();
      } catch (e) {
        debugPrint('Error updating page: $e');
      }
    }
  }

  Future<void> deletePage(String id) async {
    await _archiveItem(id, fromRemote: false);
  }

  Future<void> _archiveItem(String id, {required bool fromRemote}) async {
    try {
      await _dbService.archivePageRecursive(id);
      await loadDatabaseState();

      _broadcastMetadataToAllClients();
    } catch (e) {
      debugPrint('Error archiving page: $e');
    }
  }

  Future<void> restorePage(String id) async {
    await _restoreItem(id, fromRemote: false);
  }

  Future<void> _restoreItem(String id, {required bool fromRemote}) async {
    try {
      await _dbService.restorePageRecursive(id);
      await loadDatabaseState();

      _broadcastMetadataToAllClients();
    } catch (e) {
      debugPrint('Error restoring page: $e');
    }
  }

  Future<void> movePage(String id, String? newParentId) async {
    await _moveItem(id, newParentId, fromRemote: false);
  }

  Future<void> _moveItem(String id, String? newParentId, {required bool fromRemote}) async {
    final index = _pages.indexWhere((p) => p.id == id);
    if (index == -1) return;

    try {
      final movedPage = _pages[index].copyWith(
        parentId: newParentId,
        updatedAt: DateTime.now(),
      );

      await _dbService.updatePage(movedPage);
      _pages[index] = movedPage;
      notifyListeners();

      _broadcastMetadataToAllClients();
    } catch (e) {
      debugPrint('Error moving page: $e');
    }
  }

  Future<List<DbPage>> getArchivedPages() async {
    return await _dbService.getArchivedPages();
  }

  Future<void> hardDeletePage(String id) async {
    try {
      await _dbService.hardDeletePageRecursive(id);
      await loadDatabaseState();

      _broadcastMetadataToAllClients();
    } catch (e) {
      debugPrint('Error permanently deleting page: $e');
    }
  }

  // --- Card Action Handlers ---

  Future<void> addCard({
    required String pageId,
    required String type,
    required String content,
  }) async {
    final cards = await _dbService.getCards(pageId);
    final maxOrder = cards.isEmpty ? 0 : cards.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) + 1;

    final card = Card(
      id: generateId(),
      pageId: pageId,
      type: type,
      content: content,
      sortOrder: maxOrder,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _addCard(card, fromRemote: false);
  }

  Future<void> _addCard(Card card, {required bool fromRemote}) async {
    try {
      await _dbService.insertCard(card);

      await _broadcastCardsToAllClients(card.pageId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error inserting card: $e');
    }
  }

  Future<void> updateCard({
    required String id,
    required String content,
  }) async {
    final card = await _dbService.getCard(id);
    if (card == null) return;

    final updated = card.copyWith(
      content: content,
      updatedAt: DateTime.now(),
      revision: card.revision + 1,
    );
    await _updateCard(updated, fromRemote: false);
  }

  Future<void> _updateCard(Card card, {required bool fromRemote}) async {
    try {
      await _dbService.updateCard(card);

      await _broadcastCardsToAllClients(card.pageId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating card: $e');
    }
  }

  Future<void> deleteCard(String cardId) async {
    await _deleteCard(cardId, fromRemote: false);
  }

  Future<void> reorderCards({required List<String> cardIds}) async {
    if (cardIds.isEmpty) return;
    final card = await _dbService.getCard(cardIds.first);
    if (card == null) return;
    await _reorderCards(card.pageId, cardIds, fromRemote: false);
  }

  Future<void> _deleteCard(String cardId, {String? deletePageId, required bool fromRemote}) async {
    try {
      final card = await _dbService.getCard(cardId);
      final pageId = deletePageId ?? card?.pageId ?? '';

      await _dbService.deleteCard(cardId);

      if (pageId.isNotEmpty) {
        await _broadcastCardsToAllClients(pageId);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting card: $e');
    }
  }

  Future<void> _reorderCards(String pageId, List<String> cardIds, {required bool fromRemote}) async {
    try {
      await _dbService.reorderCards(pageId, cardIds);

      await _broadcastCardsToAllClients(pageId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error reordering cards: $e');
    }
  }

  // --- Workspace Handlers ---

  Future<void> _handleListWorkspaces(WebSocket sender) async {
    try {
      final paths = await _dbService.listWorkspaces();
      final names = paths.map((p) {
        final filename = p.split(Platform.pathSeparator).last;
        return filename.replaceAll('.db', '');
      }).toList();
      sender.add(jsonEncode({
        'type': 'workspace_list',
        'workspaces': names,
        'activeWorkspace': _dbService.currentWorkspaceName,
      }));
    } catch (e) {
      debugPrint('Error listing workspaces: $e');
    }
  }

  Future<void> _handleCreateWorkspace(String workspaceName, WebSocket sender) async {
    try {
      await _dbService.createWorkspace(workspaceName);
      await loadDatabaseState();
      final paths = await _dbService.listWorkspaces();
      final names = paths.map((p) {
        final filename = p.split(Platform.pathSeparator).last;
        return filename.replaceAll('.db', '');
      }).toList();
      _broadcastToAllClients({
        'type': 'workspace_status',
        'activeWorkspace': _dbService.currentWorkspaceName,
        'availableWorkspaces': names,
      });
      _broadcastMetadataToAllClients();
    } catch (e) {
      debugPrint('Error creating workspace: $e');
    }
  }

  Future<void> _handleSwitchWorkspace(String workspaceName) async {
    final workspaces = await _dbService.listWorkspaces();
    final match = workspaces.firstWhere(
      (path) => path.endsWith('$workspaceName.db'),
      orElse: () => '',
    );
    if (match.isNotEmpty) {
      await switchWorkspace(match);
    }
  }
}
