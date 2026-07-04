import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../services/server_service.dart';

class SettingsScreen extends StatefulWidget {
  final ServerService serverService;

  const SettingsScreen({super.key, required this.serverService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final ServerService _serverService;
  List<String> _workspaces = [];
  String _activeWorkspace = '';
  String _dbPathInfo = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _serverService = widget.serverService;
    _loadWorkspaceData();
  }

  Future<void> _loadWorkspaceData() async {
    setState(() => _isLoading = true);
    try {
      final workspaces = await _serverService.dbService.listWorkspaces();
      final active = _serverService.dbService.currentWorkspaceName;
      final path = _serverService.dbService.currentWorkspacePath;
      setState(() {
        _workspaces = workspaces.map((path) => p.basenameWithoutExtension(path)).toList();
        _activeWorkspace = active;
        _dbPathInfo = path;
      });
    } catch (e) {
      _showSnackBar('Error loading workspaces: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSwitchWorkspace(String name) async {
    setState(() => _isLoading = true);
    try {
      final workspaces = await _serverService.dbService.listWorkspaces();
      final match = workspaces.firstWhere(
        (path) => path.endsWith('$name.db'),
        orElse: () => '',
      );
      if (match.isNotEmpty) {
        await _serverService.switchWorkspace(match);
        await _loadWorkspaceData();
        _showSnackBar('Switched to workspace: $name');
      }
    } catch (e) {
      _showSnackBar('Failed to switch workspace: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCreateWorkspace() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        title: const Text('New Workspace'),
        content: TextField(
          controller: controller,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Workspace name (e.g. Work, Notes)',
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF3E3E3E)),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFF818CF8)),
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF818CF8),
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        await _serverService.dbService.createWorkspace(name);
        await _serverService.loadDatabaseState();
        await _loadWorkspaceData();
        _showSnackBar('Workspace created: $name');
      } catch (e) {
        _showSnackBar('Failed to create workspace: $e', isError: true);
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleDeleteWorkspace(String name) async {
    if (name == 'Personal') {
      _showSnackBar('Cannot delete default "Personal" workspace', isError: true);
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF202020),
        title: Text('Delete "$name"?'),
        content: const Text(
          'This will permanently delete this workspace and all embedded images. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        final workspaces = await _serverService.dbService.listWorkspaces();
        final match = workspaces.firstWhere((path) => path.endsWith('$name.db'), orElse: () => '');
        if (match.isNotEmpty) {
          if (_activeWorkspace == name) {
            final personalMatch = workspaces.firstWhere((path) => path.endsWith('Personal.db'), orElse: () => '');
            if (personalMatch.isNotEmpty) {
              await _serverService.switchWorkspace(personalMatch);
            }
          }
          await _serverService.dbService.deleteWorkspace(match);
          await _loadWorkspaceData();
          _showSnackBar('Workspace deleted: $name');
        }
      } catch (e) {
        _showSnackBar('Failed to delete workspace: $e', isError: true);
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleExportWorkspace() async {
    setState(() => _isLoading = true);
    try {
      final exportDir = await _serverService.dbService.getExportDirectoryPath();
      final targetPath = await _serverService.dbService.exportWorkspaceToZip(_activeWorkspace, exportDir);
      _showSnackBar('Exported workspace successfully to:\n$targetPath');
    } catch (e) {
      _showSnackBar('Failed to export workspace: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleImportWorkspace() async {
    try {
      FilePickerResult? result;
      try {
        result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['zip'],
        );
      } catch (e) {
        debugPrint('Custom pickFiles method threw error: $e. Falling back to FileType.any...');
        result = await FilePicker.platform.pickFiles(
          type: FileType.any,
        );
      }

      if (result == null || result.files.single.path == null) {
        return;
      }

      final sourcePath = result.files.single.path!;
      if (!sourcePath.toLowerCase().endsWith('.zip')) {
        _showSnackBar('Please select a valid .zip backup file', isError: true);
        return;
      }

      final defaultImportName = p.basenameWithoutExtension(sourcePath).replaceAll('Cero_Backup_', '');

      final controller = TextEditingController(text: defaultImportName);
      if (!mounted) return;
      final importName = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF202020),
          title: const Text('Import Workspace'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Specify workspace name for import. If you specify the name of an existing workspace, it will be completely overwritten with the backup data.',
                style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Workspace Name',
                  labelStyle: TextStyle(color: Color(0xFF818CF8)),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF3E3E3E)),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF818CF8)),
                  ),
                ),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF818CF8),
              ),
              child: const Text('Import'),
            ),
          ],
        ),
      );

      if (importName != null && importName.isNotEmpty) {
        setState(() => _isLoading = true);
        await _serverService.dbService.importWorkspaceFromZip(sourcePath, importName);
        
        final workspaces = await _serverService.dbService.listWorkspaces();
        final match = workspaces.firstWhere((path) => path.endsWith('$importName.db'), orElse: () => '');
        if (match.isNotEmpty) {
          await _serverService.switchWorkspace(match);
        }
        await _loadWorkspaceData();
        _showSnackBar('Workspace "$importName" imported and loaded!');
      }
    } catch (e) {
      _showSnackBar('Failed to import workspace: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 12),
        ),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF818CF8),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings & Backups',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: const Color(0xFF191919),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF818CF8)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSectionHeader('DATABASE INFORMATION'),
                  _buildPathCard(),
                  const SizedBox(height: 24),
                  _buildSectionHeader('BACKUP & SINGLE-FILE SYNC'),
                  _buildBackupCard(),
                  const SizedBox(height: 24),
                  _buildSectionHeader('WORKSPACES'),
                  _buildWorkspaceCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Color(0xFF64748B),
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildPathCard() {
    return Card(
      color: const Color(0xFF202020),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF2C2C2C)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.folder_open, color: Color(0xFF818CF8), size: 18),
                SizedBox(width: 8),
                Text(
                  'Local Database Location',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF191919),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                _dbPathInfo,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFFCBD5E1),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your mobile device holds the primary source of truth. You can back up this database folder directly or overwrite it using a single file.',
              style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupCard() {
    return Card(
      color: const Color(0xFF202020),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF2C2C2C)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.unarchive_outlined, color: Color(0xFF818CF8), size: 18),
                SizedBox(width: 8),
                Text(
                  'Single-File Import / Export (.zip)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Exporting compresses your entire database (.db) and your workspace media images into a single portable ZIP archive. Importing decompresses and loads them safely.',
              style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.4),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _handleExportWorkspace,
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Export Workspace'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF818CF8).withValues(alpha: 0.15),
                      foregroundColor: const Color(0xFF818CF8),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _handleImportWorkspace,
                    icon: const Icon(Icons.upload, size: 16),
                    label: const Text('Import Backup'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF818CF8),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaceCard() {
    return Card(
      color: const Color(0xFF202020),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFF2C2C2C)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.dashboard_customize_outlined, color: Color(0xFF818CF8), size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Manage Workspaces',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: _handleCreateWorkspace,
                  icon: const Icon(Icons.add, color: Color(0xFF818CF8), size: 18),
                  tooltip: 'Create Workspace',
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _workspaces.length,
              itemBuilder: (context, index) {
                final ws = _workspaces[index];
                final isActive = ws == _activeWorkspace;
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFF818CF8).withValues(alpha: 0.08) : const Color(0xFF191919),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isActive ? const Color(0xFF818CF8).withValues(alpha: 0.3) : const Color(0xFF2C2C2C),
                    ),
                  ),
                  child: ListTile(
                    dense: true,
                    title: Text(
                      ws,
                      style: TextStyle(
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                        color: isActive ? const Color(0xFF818CF8) : Colors.white,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isActive)
                          IconButton(
                            icon: const Icon(Icons.swap_horiz, size: 16, color: Colors.grey),
                            tooltip: 'Switch to workspace',
                            onPressed: () => _handleSwitchWorkspace(ws),
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                          tooltip: 'Delete workspace',
                          onPressed: () => _handleDeleteWorkspace(ws),
                        ),
                      ],
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
}
