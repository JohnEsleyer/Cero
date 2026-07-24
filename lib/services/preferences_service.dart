import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class PreferencesService {
  static const String _fileName = 'preferences.json';

  bool autoJumpToLastCard = false;

  Future<void> load() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_fileName');
      if (await file.exists()) {
        final content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);
        autoJumpToLastCard = data['auto_jump_to_last_card'] ?? false;
      }
    } catch (_) {}
  }

  Future<void> save() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_fileName');
      final data = {
        'auto_jump_to_last_card': autoJumpToLastCard,
      };
      await file.writeAsString(jsonEncode(data));
    } catch (_) {}
  }

  Future<void> setAutoJumpToLastCard(bool val) async {
    autoJumpToLastCard = val;
    await save();
  }
}
