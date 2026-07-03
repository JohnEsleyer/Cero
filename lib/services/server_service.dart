import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/db_item.dart';

class ClientConnection {
  final WebSocket socket;
  final String remoteAddress;
  ClientConnection(this.socket, this.remoteAddress);
}

class ServerService extends ChangeNotifier {
  HttpServer? _httpServer;
  RawDatagramSocket? _udpSocket;
  Timer? _udpBroadcastTimer;
  
  bool _isRunning = false;
  String _localIp = 'Unknown';
  final int _wsPort = 9090;
  final int _udpPort = 9100;
  
  final List<ClientConnection> _clients = [];
  final List<DbItem> _dbItems = [
    DbItem(
      id: '1',
      title: 'Welcome to PocketDatabase',
      content: 'This database is hosted on the mobile app and synced to desktop!',
      updatedAt: DateTime.now(),
    ),
    DbItem(
      id: '2',
      title: 'Real-time Sync',
      content: 'Add or edit items on either device to see instant synchronization.',
      updatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    ),
  ];

  bool get isRunning => _isRunning;
  String get localIp => _localIp;
  int get wsPort => _wsPort;
  List<ClientConnection> get clients => _clients;
  List<DbItem> get dbItems => _dbItems;

  // Initialize service by getting local IP
  Future<void> init() async {
    await updateLocalIp();
  }

  Future<void> updateLocalIp() async {
    try {
      List<NetworkInterface> interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      
      if (interfaces.isNotEmpty) {
        // Try to find Wi-Fi or standard network interface
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

      // 1. Start HTTP Server for WebSockets
      _httpServer = await HttpServer.bind(InternetAddress.anyIPv4, _wsPort);
      debugPrint('WebSocket server listening on $_localIp:$_wsPort');

      _httpServer!.listen((HttpRequest request) {
        if (request.uri.path == '/ws') {
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

      // 2. Start UDP Broadcast socket
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udpSocket!.broadcastEnabled = true;
      debugPrint('UDP Broadcast socket bound');

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

    // Close all active client connections
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
        'app': 'pocketdatabase',
        'port': _wsPort,
        'ip': _localIp,
        'deviceName': Platform.isAndroid 
            ? 'Android Device' 
            : Platform.isIOS 
                ? 'iOS Device' 
                : 'Flutter Mobile Desktop (${Platform.operatingSystem})',
      };
      
      final String payload = jsonEncode(beaconData);
      final List<int> dataToSend = utf8.encode(payload);
      
      // Broadcast to standard broadcast address
      _udpSocket!.send(dataToSend, InternetAddress('255.255.255.255'), _udpPort);
    } catch (e) {
      debugPrint('UDP broadcast error: $e');
    }
  }

  // Handle a new WebSocket connection
  void _handleNewClient(WebSocket socket, String remoteAddress) {
    final clientConnection = ClientConnection(socket, remoteAddress);
    _clients.add(clientConnection);
    notifyListeners();
    debugPrint('New client connected from $remoteAddress');

    // Send initial state to the newly connected client
    _syncDbStateToClient(socket);

    socket.listen(
      (message) {
        _handleIncomingMessage(socket, message);
      },
      onDone: () {
        _clients.remove(clientConnection);
        notifyListeners();
        debugPrint('Client disconnected: $remoteAddress');
      },
      onError: (error) {
        _clients.remove(clientConnection);
        notifyListeners();
        debugPrint('Client socket error: $error ($remoteAddress)');
      },
    );
  }

  // Parse and process incoming commands from clients
  void _handleIncomingMessage(WebSocket sender, dynamic message) {
    if (message is! String) return;

    try {
      final data = jsonDecode(message);
      final String type = data['type'] ?? '';

      switch (type) {
        case 'add':
          if (data['item'] != null) {
            final newItem = DbItem.fromMap(data['item']);
            _addItem(newItem, fromRemote: true);
          }
          break;
        case 'update':
          if (data['item'] != null) {
            final updatedItem = DbItem.fromMap(data['item']);
            _updateItem(updatedItem, fromRemote: true);
          }
          break;
        case 'delete':
          final String id = data['id'] ?? '';
          if (id.isNotEmpty) {
            _deleteItem(id, fromRemote: true);
          }
          break;
        default:
          debugPrint('Unknown message type: $type');
      }
    } catch (e) {
      debugPrint('Error parsing client message: $e');
    }
  }

  // Sync entire database to a specific client
  void _syncDbStateToClient(WebSocket socket) {
    try {
      final syncMessage = {
        'type': 'sync',
        'data': _dbItems.map((item) => item.toMap()).toList(),
      };
      socket.add(jsonEncode(syncMessage));
    } catch (e) {
      debugPrint('Error syncing database state: $e');
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

  // --- Local Database Actions ---

  void addItem(String title, String content) {
    final newItem = DbItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      content: content,
      updatedAt: DateTime.now(),
    );
    _addItem(newItem, fromRemote: false);
  }

  void _addItem(DbItem item, {required bool fromRemote}) {
    // Check if item already exists (avoid duplicates)
    if (_dbItems.any((i) => i.id == item.id)) return;
    
    _dbItems.add(item);
    notifyListeners();

    // Broadcast the add event to all clients
    _broadcastToAllClients({
      'type': 'add',
      'item': item.toMap(),
    });
  }

  void updateItem(String id, String title, String content) {
    final index = _dbItems.indexWhere((item) => item.id == id);
    if (index != -1) {
      final updatedItem = _dbItems[index].copyWith(
        title: title,
        content: content,
        updatedAt: DateTime.now(),
      );
      _updateItem(updatedItem, fromRemote: false);
    }
  }

  void _updateItem(DbItem item, {required bool fromRemote}) {
    final index = _dbItems.indexWhere((i) => i.id == item.id);
    if (index != -1) {
      _dbItems[index] = item;
      notifyListeners();

      // Broadcast update event to all clients
      _broadcastToAllClients({
        'type': 'update',
        'item': item.toMap(),
      });
    }
  }

  void deleteItem(String id) {
    _deleteItem(id, fromRemote: false);
  }

  void _deleteItem(String id, {required bool fromRemote}) {
    _dbItems.removeWhere((item) => item.id == id);
    notifyListeners();

    // Broadcast delete event to all clients
    _broadcastToAllClients({
      'type': 'delete',
      'id': id,
    });
  }
}
