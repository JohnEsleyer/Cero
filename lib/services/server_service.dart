import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/page_model.dart';
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

  // Initialize service, fetch local IP, and load initial database state
  Future<void> init() async {
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

  // Start the server (WebSocket + UDP broadcast)
  Future<bool> startServer() async {
    if (_isRunning) return true;

    try {
      await updateLocalIp();
      await loadDatabaseState();

      // 1. Start HTTP Server for WebSockets
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, _wsPort);
      debugPrint('Cero Sync Server listening on $_localIp:$_wsPort');

      _httpServer!.listen((HttpRequest request) {
        if (request.uri.path == '/ws') {
          // Validate auth PIN from query parameter
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

      // 2. Generate auth PIN
      _authPin = _generatePin();

      // 3. Start UDP multicast socket
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpSocket!.broadcastEnabled = true;
      // Join multicast group for better router traversal
      _udpSocket!.joinMulticast(InternetAddress(_multicastAddr));
      debugPrint('UDP Multicast socket bound on $_multicastAddr');

      // Start periodic broadcast every 2 seconds
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

  // Stop the server
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

  // Broadcast discovery beacon over UDP
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
      // Also send to broadcast address for legacy support
      _udpSocket!.send(dataToSend, InternetAddress('255.255.255.255'), _udpPort);
    } catch (e) {
      debugPrint('UDP broadcast error: $e');
    }
  }

  // Handle a new WebSocket connection
  void _handleNewClient(WebSocket socket, String remoteAddress) {
    debugPrint('New connection from $remoteAddress');

    // Send pairing request first
    final pairMsg = {
      'type': 'pairing_required',
      'remoteAddress': remoteAddress,
    };
    socket.add(jsonEncode(pairMsg));

    // Add to pending connections
    final completer = Completer<bool>();
    final pending = PendingConnection(socket, remoteAddress, completer);
    _pendingConnections.add(pending);
    notifyListeners();
    debugPrint('Pending pairing from: $remoteAddress');

    // Attach listener immediately to avoid losing messages
    socket.listen(
      (message) {
        // Only process messages if client has been approved
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

    // Wait for approval via completer
    completer.future.then((approved) {
      _pendingConnections.remove(pending);
      _handleApprovedClient(socket, remoteAddress, approved);
    });
  }

  // After pairing approval
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

    // Send pairing accepted
    final acceptMsg = {'type': 'pairing_accepted'};
    socket.add(jsonEncode(acceptMsg));

    // Send metadata-only sync to build the navigation tree
    _syncMetadataToClient(socket);
  }

  // Approve or reject a pending connection
  Future<void> approvePendingClient(int index) async {
    if (index < 0 || index >= _pendingConnections.length) return;
    _pendingConnections[index].completer.complete(true);
  }

  Future<void> rejectPendingClient(int index) async {
    if (index < 0 || index >= _pendingConnections.length) return;
    _pendingConnections[index].completer.complete(false);
  }

  // Parse and process incoming commands from clients
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
            final updatedPage = DbPage.fromMap(data['item']);
            await _updateItem(updatedPage, fromRemote: true);
          }
          break;
        case 'delete':
          // Legacy support - treat as archive
          final String id = data['id'] ?? '';
          if (id.isNotEmpty) {
            await _archiveItem(id, fromRemote: true);
          }
          break;
        case 'archive':
          final String id = data['id'] ?? '';
          if (id.isNotEmpty) {
            await _archiveItem(id, fromRemote: true);
          }
          break;
        case 'restore':
          final String id = data['id'] ?? '';
          if (id.isNotEmpty) {
            await _restoreItem(id, fromRemote: true);
          }
          break;
        case 'fetch':
          final String fetchId = data['id'] ?? '';
          if (fetchId.isNotEmpty) {
            await _sendPageContent(sender, fetchId);
          }
          break;
        case 'move':
          final String moveId = data['id'] ?? '';
          final String newParentId = data['parent_id'] ?? '';
          if (moveId.isNotEmpty) {
            await _moveItem(moveId, newParentId.isEmpty ? null : newParentId, fromRemote: true);
          }
          break;
        default:
          debugPrint('Unknown message type: $type');
      }
    } catch (e) {
      debugPrint('Error parsing client message: $e');
    }
  }

  // Generate random 4-digit auth PIN
  String _generatePin() {
    final random = Random.secure();
    return '${1000 + random.nextInt(9000)}';
  }

  // Sync metadata only (no content) to quickly build navigation tree
  void _syncMetadataToClient(WebSocket socket) {
    try {
      final metaData = _pages.map((page) => {
        'id': page.id,
        'parent_id': page.parentId,
        'title': page.title,
        'emoji': page.emoji,
        'created_at': page.createdAt.toIso8601String(),
        'updated_at': page.updatedAt.toIso8601String(),
        'is_archived': page.isArchived ? 1 : 0,
        'sort_order': page.sortOrder,
        'revision': page.revision,
      }).toList();

      final syncMessage = {
        'type': 'sync',
        'data': metaData,
      };
      socket.add(jsonEncode(syncMessage));
    } catch (e) {
      debugPrint('Error syncing metadata: $e');
    }
  }

  // Sync entire database to a specific client (full content)
  void _syncDbStateToClient(WebSocket socket) {
    try {
      final syncMessage = {
        'type': 'sync',
        'data': _pages.map((page) => page.toMap()).toList(),
      };
      socket.add(jsonEncode(syncMessage));
    } catch (e) {
      debugPrint('Error syncing database state: $e');
    }
  }

  // Fetch full content for a specific page
  Future<void> _sendPageContent(WebSocket socket, String pageId) async {
    try {
      final page = _pages.firstWhere((p) => p.id == pageId, orElse: () => _pages.isNotEmpty ? _pages.first : DbPage(id: '', parentId: null, title: '', content: '', emoji: '', createdAt: DateTime.now(), updatedAt: DateTime.now()));
      if (page.id.isEmpty) return;
      
      final contentMsg = {
        'type': 'content',
        'id': page.id,
        'content': page.content,
      };
      socket.add(jsonEncode(contentMsg));
    } catch (e) {
      debugPrint('Error fetching page content: $e');
    }
  }

  // Broadcast database update to all clients
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

  // Generate unique alphanumeric string as ID
  static String generateId() {
    final random = Random.secure();
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(16, (index) => chars[random.nextInt(chars.length)]).join();
  }

  // --- Database Action Handlers ---

  Future<void> addPage({String? parentId, required String title, required String content, required String emoji}) async {
    final newPage = DbPage(
      id: generateId(),
      parentId: parentId,
      title: title,
      content: content,
      emoji: emoji,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _addItem(newPage, fromRemote: false);
  }

  Future<void> _addItem(DbPage page, {required bool fromRemote}) async {
    if (_pages.any((p) => p.id == page.id)) return;
    
    // Save to SQLite
    try {
      await _dbService.insertPage(page);
      _pages.add(page);
      notifyListeners();

      // Broadcast add to all clients (include content since it's a new page)
      _broadcastToAllClients({
        'type': 'add',
        'item': page.toMap(),
      });
    } catch (e) {
      debugPrint('Error inserting page: $e');
    }
  }

  Future<void> updatePage({required String id, required String title, required String content, required String emoji}) async {
    final index = _pages.indexWhere((p) => p.id == id);
    if (index != -1) {
      final updatedPage = _pages[index].copyWith(
        title: title,
        content: content,
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
      // Reject stale updates from remote when revision is explicitly provided
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

        // Save to SQLite
        await _dbService.updatePage(updatedPage);
        _pages[index] = updatedPage;
        notifyListeners();

        // Broadcast update to all clients
        _broadcastToAllClients({
          'type': 'update',
          'item': updatedPage.toMap(),
        });
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
      // 1. Soft-delete recursively in SQLite
      await _dbService.archivePageRecursive(id);
      
      // 2. Reload database state
      await loadDatabaseState();

      // 3. Broadcast archive event to all clients
      _broadcastToAllClients({
        'type': 'archive',
        'id': id,
      });
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

      _broadcastToAllClients({
        'type': 'restore',
        'id': id,
      });
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

      _broadcastToAllClients({
        'type': 'move',
        'id': id,
        'parent_id': newParentId,
      });
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

      _broadcastToAllClients({
        'type': 'hard_delete',
        'id': id,
      });
    } catch (e) {
      debugPrint('Error permanently deleting page: $e');
    }
  }
}
