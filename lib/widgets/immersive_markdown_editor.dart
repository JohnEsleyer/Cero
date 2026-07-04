import 'package:flutter/material.dart';

class ImmersiveMarkdownEditor extends StatefulWidget {
  final String cardId;
  final String initialContent;
  final ValueChanged<String> onSave;

  const ImmersiveMarkdownEditor({
    super.key,
    required this.cardId,
    required this.initialContent,
    required this.onSave,
  });

  @override
  State<ImmersiveMarkdownEditor> createState() => _ImmersiveMarkdownEditorState();
}

class _ImmersiveMarkdownEditorState extends State<ImmersiveMarkdownEditor> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _insertMarkdown(String prefix, String suffix) {
    final text = _controller.text;
    final selection = _controller.selection;
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(0, text.length);
    final selected = text.substring(start, end);
    final newText =
        text.substring(0, start) +
        prefix +
        selected +
        suffix +
        text.substring(end);
    _controller.text = newText;
    final newPos = start + prefix.length + selected.length;
    _controller.selection = TextSelection.collapsed(offset: newPos);
  }

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'card_markdown_${widget.cardId}',
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E1E1E),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close, color: Color(0xFFCBD5E1)),
            onPressed: () {
              widget.onSave(_controller.text);
              Navigator.pop(context);
            },
          ),
          title: const Text(
            'Edit Markdown',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                widget.onSave(_controller.text);
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
        body: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.6,
                    fontFamily: 'monospace',
                    color: Color(0xFFE2E8F0),
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Type your markdown content here...',
                    hintStyle: TextStyle(color: Color(0xFF4A4A4A)),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            _buildToolbar(),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          border: Border(
            top: BorderSide(color: Color(0xFF2E2E2E), width: 0.5),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _toolbarIconBtn(Icons.format_bold, () => _insertMarkdown('**', '**')),
            _toolbarIconBtn(Icons.format_italic, () => _insertMarkdown('*', '*')),
            _toolbarIconBtn(Icons.title, () => _insertMarkdown('## ', '')),
            _toolbarIconBtn(Icons.format_list_bulleted, () => _insertMarkdown('- ', '')),
            _toolbarIconBtn(Icons.check_box_outlined, () => _insertMarkdown('- [ ] ', '')),
            _toolbarIconBtn(Icons.code, () => _insertMarkdown('`', '`')),
            _toolbarIconBtn(Icons.wrap_text, () => _insertMarkdown('```\n', '\n```')),
          ],
        ),
      ),
    );
  }

  Widget _toolbarIconBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Icon(icon, color: const Color(0xFFCBD5E1), size: 20),
      ),
    );
  }
}
