import 'dart:io';
import 'package:flutter/foundation.dart';
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
    
    // Windows Debug環境ではIsar Inspectorを無効化（VM Serviceとの干渉を避ける）
    final enableInspector = !(Platform.isWindows && kDebugMode);
    
    debugPrint('[Database] Opening Isar...');
    debugPrint('[Database] Platform: ${Platform.operatingSystem}');
    debugPrint('[Database] Debug Mode: $kDebugMode');
    debugPrint('[Database] Inspector Enabled: $enableInspector');
    
    _isar = await Isar.open(
      [MessageSchema],
      directory: dir.path,
      inspector: enableInspector, // Windows Debugでは無効化
    );
    
    debugPrint('[Database] Isar opened successfully');
    return _isar!;
  }

  static Future<void> close() async {
    debugPrint('[Database] Closing Isar...');
    await _isar?.close();
    _isar = null;
    debugPrint('[Database] Isar closed');
  }
}

