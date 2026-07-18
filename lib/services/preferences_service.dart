import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class PreferencesService {
  static const String _fileName = 'preferences.json';

  bool defaultToBlockView = false;
  bool autoJumpToLastCard = false;

  Future<void> load() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_fileName');
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);
        defaultToBlockView = data['default_to_block_view'] ?? false;
        autoJumpToLastCard = data['auto_jump_to_last_card'] ?? false;
      }
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_fileName');
      final data = {
        'default_to_block_view': defaultToBlockView,
        'auto_jump_to_last_card': autoJumpToLastCard,
      };
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<void> setDefaultToBlockView(bool val) async {
    defaultToBlockView = val;
    await save();
  }

  Future<void> setAutoJumpToLastCard(bool val) async {
    autoJumpToLastCard = val;
    await save();
  }
}
