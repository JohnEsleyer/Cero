
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/card_model.dart' as models;

class SitesCard extends StatefulWidget {
  final models.Card card;
  final ValueChanged<String> onContentChanged;
  final VoidCallback? onDelete;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const SitesCard({
    super.key,
    required this.card,
    required this.onContentChanged,
    this.onDelete,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  State<SitesCard> createState() => _SitesCardState();
}

class _SitesCardState extends State<SitesCard> {
  String _name = 'Interactive Site Widget';
  String _description = 'Sandboxed HTML preview widget';
  String _html = '';

  // Background Live serving variables
  HttpServer? _backgroundServer;
  String? _backgroundServerUrl;
  bool _isLive = false;

  @override
  void initState() {
    super.initState();
    _parseContent();
  }

  @override
  void didUpdateWidget(SitesCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.card.id != widget.card.id || oldWidget.card.content != widget.card.content) {
      _parseContent();
    }
  }

  @override
  void dispose() {
    _stopBackgroundServer();
    super.dispose();
  }

  void _parseContent() {
    try {
      final parsed = jsonDecode(widget.card.content);
      _name = parsed['name'] ?? 'Interactive Site Widget';
      _description = parsed['description'] ?? 'Sandboxed HTML preview widget';
      _html = parsed['html'] ?? '';
    } catch (_) {
      _name = 'Interactive Site Widget';
      _description = 'Sandboxed HTML preview widget';
      _html = widget.card.content;
    }
  }

  void _save(String name, String description, String html) {
    final combined = jsonEncode({
      'name': name,
      'description': description,
      'html': html,
    });
    widget.onContentChanged(combined);
  }

  Future<void> _startBackgroundServer() async {
    if (_backgroundServer != null) {
      await _stopBackgroundServer();
    }
    try {
      _backgroundServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = _backgroundServer!.port;
      setState(() {
        _backgroundServerUrl = 'http://127.0.0.1:$port';
        _isLive = true;
      });

      _backgroundServer!.listen((HttpRequest request) {
        request.response
          ..headers.contentType = ContentType.html
          ..write(_html)
          ..close();
      });
    } catch (e) {
      debugPrint('Error starting card background server: $e');
    }
  }

  Future<void> _stopBackgroundServer() async {
    if (_backgroundServer != null) {
      await _backgroundServer!.close(force: true);
      _backgroundServer = null;
      setState(() {
        _backgroundServerUrl = null;
        _isLive = false;
      });
    }
  }

  void _openSandboxWorkspace() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SitesSandboxWorkspace(
          initialName: _name,
          initialDescription: _description,
          initialHtml: _html,
          onSave: (name, description, html) {
            setState(() {
              _name = name;
              _description = description;
              _html = html;
            });
            _save(name, description, html);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(
          color: Color(0xFF2E2E2E),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildToolbar(),
          InkWell(
            onTap: _openSandboxWorkspace,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF818CF8).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        const Icon(
                          Icons.web,
                          color: Color(0xFF818CF8),
                          size: 24,
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _isLive ? Colors.green : Colors.redAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              _name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: _isLive ? Colors.green.withOpacity(0.1) : Colors.redAccent.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _isLive ? "LIVE" : "STOPPED",
                                style: TextStyle(
                                  color: _isLive ? Colors.green : Colors.redAccent,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _isLive && _backgroundServerUrl != null ? _backgroundServerUrl! : _description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _isLive ? const Color(0xFF818CF8) : const Color(0xFF64748B),
                            fontSize: 12,
                            fontFamily: _isLive ? 'monospace' : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFF2E2E2E), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _openSandboxWorkspace,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.web,
                    size: 16,
                    color: Color(0xFF64748B),
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Workspace',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          // Play/Stop toggle button
          IconButton(
            icon: Icon(_isLive ? Icons.stop : Icons.play_arrow, size: 16),
            color: _isLive ? Colors.redAccent : Colors.greenAccent,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () {
              if (_isLive) {
                _stopBackgroundServer();
              } else {
                _startBackgroundServer();
              }
            },
            tooltip: _isLive ? 'Stop serving local address' : 'Serve local address',
          ),
          if (widget.onMoveUp != null)
            _actionBtn(Icons.arrow_upward, widget.onMoveUp!),
          if (widget.onMoveDown != null)
            _actionBtn(Icons.arrow_downward, widget.onMoveDown!),
          if (widget.onDelete != null)
            _actionBtn(
              Icons.delete_outline,
              widget.onDelete!,
              color: const Color(0xFFF87171),
            ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, VoidCallback onPressed, {Color? color}) {
    return IconButton(
      icon: Icon(icon, size: 16),
      padding: const EdgeInsets.all(2),
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      onPressed: onPressed,
      color: color ?? const Color(0xFF64748B),
    );
  }
}

class SitesSandboxWorkspace extends StatefulWidget {
  final String initialName;
  final String initialDescription;
  final String initialHtml;
  final Function(String name, String description, String html) onSave;

  const SitesSandboxWorkspace({
    super.key,
    required this.initialName,
    required this.initialDescription,
    required this.initialHtml,
    required this.onSave,
  });

  @override
  State<SitesSandboxWorkspace> createState() => _SitesSandboxWorkspaceState();
}

class _SitesSandboxWorkspaceState extends State<SitesSandboxWorkspace> {
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _htmlController;

  HttpServer? _tempServer;
  String? _tempServerUrl;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descController = TextEditingController(text: widget.initialDescription);
    _htmlController = TextEditingController(text: widget.initialHtml);
    _startLocalServer();
  }

  Future<void> _startLocalServer() async {
    if (_tempServer != null) {
      await _stopLocalServer();
    }
    try {
      _tempServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = _tempServer!.port;
      setState(() {
        _tempServerUrl = 'http://127.0.0.1:$port';
      });

      _tempServer!.listen((HttpRequest request) {
        request.response
          ..headers.contentType = ContentType.html
          ..write(_htmlController.text)
          ..close();
      });
    } catch (e) {
      debugPrint('Error starting temporary HTTP server: $e');
    }
  }

  Future<void> _stopLocalServer() async {
    if (_tempServer != null) {
      await _tempServer!.close(force: true);
      _tempServer = null;
      _tempServerUrl = null;
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _launchSystemBrowser(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('url_launcher failed, trying native OS fallback: $e');
      if (Platform.isWindows) {
        await Process.run('start', [url], runInShell: true);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _htmlController.dispose();
    _stopLocalServer();
    super.dispose();
  }

  void _triggerSave() {
    widget.onSave(
      _nameController.text,
      _descController.text,
      _htmlController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Color(0xFFCBD5E1)),
            onPressed: () {
              _triggerSave();
              Navigator.pop(context);
            },
          ),
          title: const Text(
            'HTML Sandbox Workspace',
            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _triggerSave();
                Navigator.pop(context);
              },
              child: const Text(
                'Save',
                style: TextStyle(color: Color(0xFF818CF8), fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            indicatorColor: Color(0xFF818CF8),
            labelColor: Color(0xFF818CF8),
            unselectedLabelColor: Color(0xFF64748B),
            tabs: [
              Tab(icon: Icon(Icons.edit_note, size: 20), text: 'Code Editor'),
              Tab(icon: Icon(Icons.settings_input_antenna, size: 20), text: 'Local Server'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildEditorTab(),
            _buildRenderTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SITE NAME',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFF818CF8),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF1E1E1E),
              hintText: 'Enter site name',
              hintStyle: const TextStyle(color: Color(0xFF4A4A4A)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Color(0xFF2E2E2E)),
                borderRadius: BorderRadius.circular(6),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Color(0xFF818CF8)),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onChanged: (_) => _triggerSave(),
          ),
          const SizedBox(height: 16),
          const Text(
            'SITE SHORT DESCRIPTION',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFF818CF8),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _descController,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF1E1E1E),
              hintText: 'Enter short description',
              hintStyle: const TextStyle(color: Color(0xFF4A4A4A)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Color(0xFF2E2E2E)),
                borderRadius: BorderRadius.circular(6),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Color(0xFF818CF8)),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onChanged: (_) => _triggerSave(),
          ),
          const SizedBox(height: 16),
          const Text(
            'HTML CODE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFF818CF8),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _htmlController,
            maxLines: 15,
            style: const TextStyle(
              color: Color(0xFFE2E8F0),
              fontSize: 13,
              fontFamily: 'monospace',
              height: 1.5,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFF121212),
              hintText: '<h1>Welcome</h1>\n<p>HTML code snippet...</p>',
              hintStyle: const TextStyle(color: Color(0xFF4A4A4A)),
              contentPadding: const EdgeInsets.all(12),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Color(0xFF2E2E2E)),
                borderRadius: BorderRadius.circular(6),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: Color(0xFF818CF8)),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onChanged: (_) => _triggerSave(),
          ),
        ],
      ),
    );
  }

  Widget _buildRenderTab() {
    final isRunning = _tempServerUrl != null;

    return Container(
      color: const Color(0xFF121212),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(
            Icons.dns_outlined,
            size: 64,
            color: Color(0xFF818CF8),
          ),
          const SizedBox(height: 16),
          const Text(
            'Local Sandbox Server',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Serve your custom HTML locally and view it directly in your system browser or webview.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isRunning
                    ? const Color(0xFF818CF8).withOpacity(0.3)
                    : const Color(0xFF2E2E2E),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Server Status:',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: isRunning
                            ? Colors.green.withOpacity(0.1)
                            : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isRunning ? 'RUNNING' : 'STOPPED',
                        style: TextStyle(
                          color: isRunning ? Colors.green : Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                if (isRunning) ...[
                  const Divider(height: 24, color: Color(0xFF2E2E2E)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Local Address:',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      SelectableText(
                        _tempServerUrl!,
                        style: const TextStyle(
                          color: Color(0xFF818CF8),
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () async {
              if (!isRunning) {
                await _startLocalServer();
              }
              if (_tempServerUrl != null) {
                await _launchSystemBrowser(_tempServerUrl!);
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: Text(isRunning ? 'Open System Browser' : 'Start Server & Open Browser'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF818CF8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          if (isRunning) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _stopLocalServer,
              icon: const Icon(Icons.stop),
              label: const Text('Stop Server'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: const BorderSide(color: Colors.redAccent),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}