import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/page_model.dart';
import '../models/card_model.dart';
import 'database_service.dart';
import 'multicast_lock_helper.dart';

class BackgroundServerRegistry {
  static final Set<String> activeServers = {};
}

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

class DiscoveredServer {
  final String ip;
  final int port;
  final String deviceName;
  final String app;
  DiscoveredServer({
    required this.ip,
    required this.port,
    required this.deviceName,
    required this.app,
  });

  factory DiscoveredServer.fromMap(Map<String, dynamic> map) {
    return DiscoveredServer(
      ip: map['ip'] ?? '',
      port: map['port'] ?? 0,
      deviceName: map['deviceName'] ?? 'Unknown',
      app: map['app'] ?? '',
    );
  }
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

  // --- Client Mode Properties ---

  bool _isClientMode = false;
  WebSocket? _clientSocket;
  bool _isClientConnected = false;
  bool _isClientPaired = false;
  String _clientError = '';
  List<Card> _remoteCards = [];
  final Map<String, Completer<List<Card>>> _fetchCardsCompleters = {};
  final Map<String, List<Card>> _clientCachedCards = {};
  final List<DiscoveredServer> _discoveredServers = [];
  RawDatagramSocket? _udpDiscoverySocket;

  bool get isClientMode => _isClientMode;
  bool get isClientConnected => _isClientConnected;
  bool get isClientPaired => _isClientPaired;
  String get clientError => _clientError;
  List<Card> get remoteCards => _remoteCards;
  List<DiscoveredServer> get discoveredServers => _discoveredServers;

  // --- Metrics Properties ---

  static int totalBytesSent = 0;
  static int totalBytesReceived = 0;
  static double currentRxSpeed = 0.0;
  static double currentTxSpeed = 0.0;

  static int _lastBytesSent = 0;
  static int _lastBytesReceived = 0;
  static Timer? _speedTimer;

  static void startSpeedTracking() {
    _speedTimer?.cancel();
    _speedTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final sentDiff = totalBytesSent - _lastBytesSent;
      final recvDiff = totalBytesReceived - _lastBytesReceived;

      currentTxSpeed = sentDiff / 1024.0;
      currentRxSpeed = recvDiff / 1024.0;

      _lastBytesSent = totalBytesSent;
      _lastBytesReceived = totalBytesReceived;
    });
  }

  static int getMemoryUsageBytes() {
    try {
      return ProcessInfo.currentRss;
    } catch (_) {
      return 0;
    }
  }

  // --- Initialization ---

  Future<void> init() async {
    startSpeedTracking();
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
        NetworkInterface? bestInterface;
        for (var interface in interfaces) {
          final name = interface.name.toLowerCase();
          if (name.contains('wlan') || name.contains('ap') || name.contains('en') || name.contains('eth')) {
            bestInterface = interface;
            break;
          }
        }

        final selectedInterface = bestInterface ?? interfaces.first;

        for (var addr in selectedInterface.addresses) {
          if (!addr.isLoopback) {
            _localIp = addr.address;
            notifyListeners();
            return;
          }
        }

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
    _clientCachedCards.clear();
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
      await MulticastLockHelper.acquire();
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
            totalBytesReceived += utf8.encode('WebSocket upgrade').length;
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

    await MulticastLockHelper.release();

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

      if (_localIp != '127.0.0.1' && _localIp.contains('.')) {
        final parts = _localIp.split('.');
        if (parts.length == 4) {
          final subnetBroadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
          _udpSocket!.send(dataToSend, InternetAddress(subnetBroadcast), _udpPort);
        }
      }
    } catch (e) {
      debugPrint('UDP broadcast error: $e');
    }
  }

  // --- Client Mode: Discovery ---

  Future<void> startDiscovery() async {
    if (_udpDiscoverySocket != null) return;
    try {
      _udpDiscoverySocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpDiscoverySocket!.broadcastEnabled = true;
      _udpDiscoverySocket!.joinMulticast(InternetAddress(_multicastAddr));
      _udpDiscoverySocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpDiscoverySocket!.receive();
          if (datagram != null) {
            try {
              final data = jsonDecode(utf8.decode(datagram.data));
              if (data['app'] == 'cero-journal') {
                final server = DiscoveredServer.fromMap(data);
                final exists = _discoveredServers.any((s) => s.ip == server.ip);
                if (!exists) {
                  _discoveredServers.add(server);
                  notifyListeners();
                }
              }
            } catch (_) {}
          }
        }
      });
      debugPrint('Discovery socket listening for beacons');
    } catch (e) {
      debugPrint('Error starting discovery: $e');
    }
  }

  void stopDiscovery() {
    _discoveredServers.clear();
    _udpDiscoverySocket?.close();
    _udpDiscoverySocket = null;
    notifyListeners();
  }

  // --- Client Mode: Connection ---

  Future<bool> connectToHost(String host, int port, String pin) async {
    try {
      _clientError = '';
      final uri = 'ws://$host:$port/ws?pin=$pin';
      final socket = await WebSocket.connect(uri);
      _clientSocket = socket;
      _isClientConnected = true;
      _isClientPaired = false;
      notifyListeners();

      socket.listen(
        (message) {
          if (message is String) {
            totalBytesReceived += utf8.encode(message).length;
          }
          _handleClientModeIncomingMessage(message as String);
        },
        onDone: () {
          _isClientConnected = false;
          _isClientPaired = false;
          notifyListeners();
          debugPrint('Disconnected from host');
        },
        onError: (error) {
          _clientError = error.toString();
          _isClientConnected = false;
          _isClientPaired = false;
          notifyListeners();
          debugPrint('Client socket error: $error');
        },
      );

      return true;
    } catch (e) {
      _clientError = e.toString();
      _isClientConnected = false;
      notifyListeners();
      debugPrint('Failed to connect to host: $e');
      return false;
    }
  }

  Future<void> disconnectFromHost() async {
    _clientSocket?.close(WebSocketStatus.goingAway, 'Client disconnecting');
    _clientSocket = null;
    _isClientConnected = false;
    _isClientPaired = false;
    _clientError = '';
    _pages.clear();
    _remoteCards.clear();
    _clientCachedCards.clear();
    notifyListeners();
  }

  void enterClientMode() {
    _isClientMode = true;
    stopServer();
    notifyListeners();
  }

  void exitClientMode() {
    _isClientMode = false;
    disconnectFromHost();
    stopDiscovery();
    loadDatabaseState();
    notifyListeners();
  }

  // --- Client Mode: Incoming Message Handler ---

  void _handleClientModeIncomingMessage(String message) {
    try {
      final data = jsonDecode(message);
      final String type = data['type'] ?? '';

      switch (type) {
        case 'pairing_required':
          debugPrint('Pairing required, waiting for host approval...');
          break;
        case 'pairing_accepted':
          _isClientPaired = true;
          notifyListeners();
          debugPrint('Pairing accepted by host');
          break;
        case 'pairing_rejected':
          _clientError = 'Connection rejected by host';
          notifyListeners();
          break;
        case 'workspace_status':
          break;
        case 'sync':
          final List<dynamic> rawData = data['data'] ?? [];
          _pages = rawData.map((m) => DbPage.fromMap(Map<String, dynamic>.from(m))).toList();
          notifyListeners();
          break;
        case 'sync_cards':
          final String pageId = data['page_id'] ?? '';
          final List<dynamic> rawCards = data['cards'] ?? [];
          final cards = rawCards.map((c) => Card.fromMap(Map<String, dynamic>.from(c))).toList();
          _clientCachedCards[pageId] = cards;
          if (_fetchCardsCompleters.containsKey(pageId)) {
            _fetchCardsCompleters[pageId]?.complete(cards);
            _fetchCardsCompleters.remove(pageId);
          }
          notifyListeners();
          break;
        case 'sync_side_pages':
          break;
        default:
          debugPrint('Unknown message from host: $type');
      }
    } catch (e) {
      debugPrint('Error handling server message: $e');
    }
  }

  // --- Client Mode: Cards ---

  Future<List<Card>> getCards(String pageId) async {
    if (!_isClientMode || !_isClientPaired) {
      return await _dbService.getCards(pageId);
    }
    if (_clientCachedCards.containsKey(pageId)) {
      return _clientCachedCards[pageId]!;
    }
    final completer = Completer<List<Card>>();
    _fetchCardsCompleters[pageId] = completer;
    final payload = jsonEncode({'type': 'fetch_cards', 'page_id': pageId});
    _clientSocket?.add(payload);
    totalBytesSent += utf8.encode(payload).length;
    try {
      final result = await completer.future.timeout(const Duration(seconds: 10));
      return result;
    } catch (e) {
      _fetchCardsCompleters.remove(pageId);
      return [];
    }
  }

  Future<List<DbPage>> getSidePages(String parentId) async {
    if (!_isClientMode || !_isClientPaired) {
      return await _dbService.getSidePages(parentId);
    }
    return _pages
        .where((p) => p.parentId == parentId && p.relationType == 'sidepage')
        .toList();
  }

  Future<List<DbPage>> getArchivedPages() async {
    return await _dbService.getArchivedPages();
  }

  // --- WebSocket Client Handling ---

  void _handleNewClient(WebSocket socket, String remoteAddress) {
    debugPrint('New connection from $remoteAddress');

    final pairMsg = {
      'type': 'pairing_required',
      'remoteAddress': remoteAddress,
    };
    final pairPayload = jsonEncode(pairMsg);
    socket.add(pairPayload);
    totalBytesSent += utf8.encode(pairPayload).length;

    final completer = Completer<bool>();
    final pending = PendingConnection(socket, remoteAddress, completer);
    _pendingConnections.add(pending);
    notifyListeners();
    debugPrint('Pending pairing from: $remoteAddress');

    socket.listen(
      (message) {
        if (message is String) {
          totalBytesReceived += utf8.encode(message).length;
        }
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
        final rejectPayload = jsonEncode(rejectMsg);
        socket.add(rejectPayload);
        totalBytesSent += utf8.encode(rejectPayload).length;
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
    final acceptPayload = jsonEncode(acceptMsg);
    socket.add(acceptPayload);
    totalBytesSent += utf8.encode(acceptPayload).length;

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
            final int? insertAt = data['insertAt'] ?? card.sortOrder;
            await _addCard(card, insertAt: insertAt, fromRemote: true);
          }
          break;
        case 'update_card':
          if (data['item'] != null) {
            final Map<String, dynamic> itemMap = Map<String, dynamic>.from(data['item']);
            final String cardId = itemMap['id'] ?? '';
            if (cardId.isNotEmpty) {
              final existingCard = await _dbService.getCard(cardId);
              if (existingCard != null) {
                final oldPageId = existingCard.pageId;
                final mergedMap = existingCard.toMap();
                itemMap.forEach((key, value) {
                  if (value != null) mergedMap[key] = value;
                });
                mergedMap['updated_at'] = DateTime.now().toIso8601String();
                final card = Card.fromMap(mergedMap);
                await _updateCard(card, fromRemote: true, oldPageId: oldPageId);
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
        totalBytesSent += utf8.encode(messageJson).length;
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
      final payload = jsonEncode(msg);
      socket.add(payload);
      totalBytesSent += utf8.encode(payload).length;
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

      final payload = jsonEncode({
        'type': 'sync',
        'data': metaData,
      });
      socket.add(payload);
      totalBytesSent += utf8.encode(payload).length;
    } catch (e) {
      debugPrint('Error syncing metadata: $e');
    }
  }

  Future<void> _sendCardsToClient(WebSocket socket, String pageId) async {
    try {
      final cards = await _dbService.getCards(pageId);
      final payload = jsonEncode({
        'type': 'sync_cards',
        'page_id': pageId,
        'cards': cards.map((c) => c.toMap()).toList(),
      });
      socket.add(payload);
      totalBytesSent += utf8.encode(payload).length;
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
    if (_isClientMode && _isClientPaired) {
      final payload = jsonEncode({'type': 'add', 'item': newPage.toMap()});
      _clientSocket?.add(payload);
      totalBytesSent += utf8.encode(payload).length;
      return newPage;
    }
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
    if (_isClientMode && _isClientPaired) {
      final payload = jsonEncode({
        'type': 'update',
        'item': {'id': id, 'title': title, 'emoji': emoji},
      });
      _clientSocket?.add(payload);
      totalBytesSent += utf8.encode(payload).length;
      return;
    }
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
    if (_isClientMode && _isClientPaired) {
      final payload = jsonEncode({'type': 'delete', 'id': id});
      _clientSocket?.add(payload);
      totalBytesSent += utf8.encode(payload).length;
      return;
    }
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
    if (_isClientMode && _isClientPaired) {
      final payload = jsonEncode({'type': 'restore', 'id': id});
      _clientSocket?.add(payload);
      totalBytesSent += utf8.encode(payload).length;
      return;
    }
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
    if (_isClientMode && _isClientPaired) {
      final payload = jsonEncode({
        'type': 'move',
        'id': id,
        'parent_id': newParentId ?? '',
      });
      _clientSocket?.add(payload);
      totalBytesSent += utf8.encode(payload).length;
      return;
    }
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
    String? comment,
    int? insertAt,
  }) async {
    if (_isClientMode && _isClientPaired) {
      final card = Card(
        id: generateId(),
        pageId: pageId,
        type: type,
        content: content,
        comment: comment ?? '',
        sortOrder: insertAt ?? 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final payload = jsonEncode({
        'type': 'add_card', 
        'item': card.toMap(),
        'insertAt': insertAt,
      });
      _clientSocket?.add(payload);
      totalBytesSent += utf8.encode(payload).length;
      return;
    }
    final cards = await _dbService.getCards(pageId);
    final targetSortOrder = insertAt ?? (cards.isEmpty ? 0 : cards.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b) + 1);

    final card = Card(
      id: generateId(),
      pageId: pageId,
      type: type,
      content: content,
      comment: comment ?? '',
      sortOrder: targetSortOrder,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await _addCard(card, insertAt: insertAt, fromRemote: false);
  }

  Future<void> _addCard(Card card, {int? insertAt, required bool fromRemote}) async {
    try {
      final existingCards = await _dbService.getCards(card.pageId);

      if (insertAt != null && insertAt >= 0 && insertAt <= existingCards.length) {
        existingCards.insert(insertAt, card);
        await _dbService.insertCard(card);
        await _dbService.reorderCards(card.pageId, existingCards.map((c) => c.id).toList());
      } else {
        await _dbService.insertCard(card);
      }

      await _broadcastCardsToAllClients(card.pageId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error inserting card: $e');
    }
  }

  Future<void> updateCard({
    required String id,
    String? content,
    String? comment,
    String? pageId,
  }) async {
    if (_isClientMode && _isClientPaired) {
      final Map<String, dynamic> updateItem = {'id': id};
      if (content != null) updateItem['content'] = content;
      if (comment != null) updateItem['comment'] = comment;
      if (pageId != null) updateItem['page_id'] = pageId;
      final payload = jsonEncode({
        'type': 'update_card',
        'item': updateItem,
      });
      _clientSocket?.add(payload);
      totalBytesSent += utf8.encode(payload).length;
      return;
    }
    final card = await _dbService.getCard(id);
    if (card == null) return;

    final oldPageId = card.pageId;

    final updated = card.copyWith(
      content: content ?? card.content,
      comment: comment ?? card.comment,
      pageId: pageId ?? card.pageId,
      updatedAt: DateTime.now(),
      revision: card.revision + 1,
    );
    await _updateCard(updated, fromRemote: false, oldPageId: oldPageId);
  }

  Future<void> _updateCard(Card card, {required bool fromRemote, String? oldPageId}) async {
    try {
      await _dbService.updateCard(card);

      await _broadcastCardsToAllClients(card.pageId);
      if (oldPageId != null && oldPageId != card.pageId) {
        await _broadcastCardsToAllClients(oldPageId);
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating card: $e');
    }
  }

  Future<void> deleteCard(String cardId) async {
    if (_isClientMode && _isClientPaired) {
      final payload = jsonEncode({'type': 'delete_card', 'id': cardId});
      _clientSocket?.add(payload);
      totalBytesSent += utf8.encode(payload).length;
      return;
    }
    await _deleteCard(cardId, fromRemote: false);
  }

  Future<void> reorderCards({required List<String> cardIds}) async {
    if (cardIds.isEmpty) return;
    if (_isClientMode && _isClientPaired) {
      final card = await _dbService.getCard(cardIds.first);
      final payload = jsonEncode({
        'type': 'reorder_cards',
        'page_id': card?.pageId ?? '',
        'order': cardIds,
      });
      _clientSocket?.add(payload);
      totalBytesSent += utf8.encode(payload).length;
      return;
    }
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
      final payload = jsonEncode({
        'type': 'workspace_list',
        'workspaces': names,
        'activeWorkspace': _dbService.currentWorkspaceName,
      });
      sender.add(payload);
      totalBytesSent += utf8.encode(payload).length;
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
