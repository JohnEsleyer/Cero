
import 'package:flutter/material.dart';

class ImmersiveCodeEditor extends StatefulWidget {
  final String cardId;
  final String initialContent;
  final ValueChanged<String> onSave;

  const ImmersiveCodeEditor({
    super.key,
    required this.cardId,
    required this.initialContent,
    required this.onSave,
  });

  @override
  State<ImmersiveCodeEditor> createState() => _ImmersiveCodeEditorState();
}

class _ImmersiveCodeEditorState extends State<ImmersiveCodeEditor> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  String _lang = 'javascript';

  @override
  void initState() {
    super.initState();
    _parseContent();
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _parseContent() {
    final raw = widget.initialContent;
    if (raw.contains('\n')) {
      final idx = raw.indexOf('\n');
      _lang = raw.substring(0, idx).trim().toLowerCase();
      final code = raw.substring(idx + 1);
      _controller = TextEditingController(text: code);
    } else {
      _lang = 'javascript';
      _controller = TextEditingController(text: raw);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _triggerSave() {
    final combined = '$_lang\n${_controller.text}';
    widget.onSave(combined);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          'Edit Code Block',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          DropdownButton<String>(
            value: _lang,
            dropdownColor: const Color(0xFF202020),
            icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF818CF8), size: 16),
            underline: const SizedBox(),
            style: const TextStyle(color: Color(0xFF818CF8), fontSize: 13, fontWeight: FontWeight.bold),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _lang = val;
                });
              }
            },
            items: const [
              DropdownMenuItem(value: 'javascript', child: Text('JS')),
              DropdownMenuItem(value: 'python', child: Text('PYTHON')),
              DropdownMenuItem(value: 'html', child: Text('HTML')),
              DropdownMenuItem(value: 'css', child: Text('CSS')),
              DropdownMenuItem(value: 'go', child: Text('GO')),
              DropdownMenuItem(value: 'dart', child: Text('DART')),
              DropdownMenuItem(value: 'json', child: Text('JSON')),
              DropdownMenuItem(value: 'bash', child: Text('BASH')),
            ],
          ),
          const SizedBox(width: 16),
          TextButton(
            onPressed: () {
              _triggerSave();
              Navigator.pop(context);
            },
            child: const Text(
              'Done',
              style: TextStyle(
                color: Color(0xFF818CF8),
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        shape: const Border(
          bottom: BorderSide(color: Color(0xFF2E2E2E), width: 0.5),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: TextField(
          controller: _controller,
          maxLines: null,
          keyboardType: TextInputType.multiline,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            fontFamily: 'monospace',
            color: Color(0xFFE2E8F0),
          ),
          decoration: const InputDecoration(
            hintText: 'Write code here...',
            hintStyle: TextStyle(color: Color(0xFF4A4A4A)),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }
}
