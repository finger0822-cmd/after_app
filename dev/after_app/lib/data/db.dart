import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import 'message_model.dart';

class Database {
  static Isar? _isar;

  static Future<Isar> get instance async {
    if (_isar != null) {
      return _isar!;
    }

    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [MessageSchema],
      directory: dir.path,
    );
    return _isar!;
  }

  static Future<void> close() async {
    await _isar?.close();
    _isar = null;
  }
}

