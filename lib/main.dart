import 'package:flutter/material.dart';
import 'services/server_service.dart';
import 'models/db_item.dart';

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
      title: 'PocketDatabase Mobile Server',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A), // Slate 900
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6366F1), // Indigo 500
          brightness: Brightness.dark,
          primary: const Color(0xFF6366F1),
          secondary: const Color(0xFF8B5CF6), // Violet 500
          surface: const Color(0xFF1E293B), // Slate 800
          background: const Color(0xFF0F172A),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1E293B),
          elevation: 2,
          margin: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        ),
      ),
      home: ServerHomeScreen(serverService: serverService),
    );
  }
}

class ServerHomeScreen extends StatefulWidget {
  final ServerService serverService;
  
  const ServerHomeScreen({super.key, required this.serverService});

  @override
  State<ServerHomeScreen> createState() => _ServerHomeScreenState();
}

class _ServerHomeScreenState extends State<ServerHomeScreen> {
  late final ServerService _serverService;

  @override
  void initState() {
    super.initState();
    _serverService = widget.serverService;
    _serverService.addListener(_onServerStateChanged);
  }

  @override
  void dispose() {
    _serverService.removeListener(_onServerStateChanged);
    super.dispose();
  }

  void _onServerStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // Show dialog to add or edit an item
  void _showItemDialog([DbItem? item]) {
    final titleController = TextEditingController(text: item?.title ?? '');
    final contentController = TextEditingController(text: item?.content ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: Text(
          item == null ? 'Create Database Record' : 'Edit Database Record',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF6366F1), width: 2),
                ),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: contentController,
              decoration: const InputDecoration(
                labelText: 'Content',
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF6366F1), width: 2),
                ),
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              final title = titleController.text.trim();
              final content = contentController.text.trim();
              if (title.isNotEmpty && content.isNotEmpty) {
                if (item == null) {
                  _serverService.addItem(title, content);
                } else {
                  _serverService.updateItem(item.id, title, content);
                }
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.storage, color: Color(0xFF6366F1)),
            SizedBox(width: 8),
            Text(
              'PocketDB Mobile',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Update IP',
            onPressed: () => _serverService.updateLocalIp(),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Network Server Status Card
          _buildStatusCard(theme),
          
          // Connected Clients Section
          _buildConnectedClientsHeader(),
          
          // Database Items List Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'Database Records',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_serverService.dbItems.length}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  onPressed: () => _showItemDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Record'),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6366F1),
                  ),
                ),
              ],
            ),
          ),
          
          // Database Items List
          Expanded(
            child: _serverService.dbItems.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    itemCount: _serverService.dbItems.length,
                    itemBuilder: (context, index) {
                      final item = _serverService.dbItems[index];
                      return _buildDbItemCard(item);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme) {
    final isRunning = _serverService.isRunning;
    
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B), // Slate 800
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRunning 
              ? const Color(0xFF6366F1).withOpacity(0.3) 
              : Colors.grey.withOpacity(0.1),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isRunning 
                ? const Color(0xFF6366F1).withOpacity(0.1) 
                : Colors.transparent,
            blurRadius: 16,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Local Sync Server',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isRunning ? Colors.green : Colors.red,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isRunning ? 'Running' : 'Stopped',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isRunning ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Switch.adaptive(
                value: isRunning,
                activeColor: const Color(0xFF6366F1),
                onChanged: (value) async {
                  if (value) {
                    await _serverService.startServer();
                  } else {
                    await _serverService.stopServer();
                  }
                },
              ),
            ],
          ),
          const Divider(height: 24, color: Color(0xFF334155)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildInfoItem('IP Address', _serverService.localIp),
              _buildInfoItem('WS Port', '${_serverService.wsPort}'),
              _buildInfoItem('UDP Port', '9100'),
            ],
          ),
          if (isRunning) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Broadcasting UDP discovery beacons...',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildConnectedClientsHeader() {
    final clientsCount = _serverService.clients.length;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.devices, size: 18, color: Color(0xFF8B5CF6)),
              const SizedBox(width: 8),
              Text(
                'Connected Desktop Clients ($clientsCount)',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          if (clientsCount > 0) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: clientsCount,
                itemBuilder: (context, index) {
                  final client = _serverService.clients[index];
                  // Using remoteAddress to display client IP
                  final clientIp = client.remoteAddress;
                  return Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.1),
                      border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.laptop, size: 14, color: Color(0xFF6366F1)),
                        const SizedBox(width: 6),
                        Text(
                          clientIp,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ] else ...[
            const SizedBox(height: 6),
            const Text(
              'No desktop clients connected. Start server and launch Wails app.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDbItemCard(DbItem item) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showItemDialog(item),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18, color: Colors.grey),
                        onPressed: () => _showItemDialog(item),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 18, color: Colors.redAccent),
                        onPressed: () => _serverService.deleteItem(item.id),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                item.content,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[300],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.cloud_done, size: 12, color: Colors.green),
                      SizedBox(width: 4),
                      Text(
                        'Synced',
                        style: TextStyle(fontSize: 11, color: Colors.green),
                      ),
                    ],
                  ),
                  Text(
                    _formatTime(item.updatedAt),
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.storage_outlined, size: 64, color: Colors.grey[700]),
          const SizedBox(height: 16),
          const Text(
            'Database is Empty',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            'Create a record above to get started.',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    final second = dateTime.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}
