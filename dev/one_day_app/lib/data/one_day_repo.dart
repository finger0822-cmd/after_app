import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../domain/one_day_message.dart';

/// One Day メッセージリポジトリ（SharedPreferences使用）
class OneDayRepo {
  static const String _key = 'one_day_messages_v1';
  static const _uuid = Uuid();

  /// 全メッセージを取得（新しい順）
  Future<List<OneDayMessage>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_key);
      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      final List<dynamic> jsonList = jsonDecode(jsonString) as List<dynamic>;
      final messages = jsonList
          .map((json) => OneDayMessage.fromJson(json as Map<String, dynamic>))
          .toList();

      // 新しい順にソート
      messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return messages;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OneDayRepo] load error: $e');
      }
      return [];
    }
  }

  /// メッセージを追加
  Future<bool> add(String text) async {
    try {
      if (text.trim().isEmpty) {
        return false;
      }

      final messages = await load();
      final newMessage = OneDayMessage(
        id: _uuid.v4(),
        text: text.trim(),
        createdAt: DateTime.now().toUtc(),
      );

      messages.add(newMessage);
      final saved = await _save(messages);
      if (kDebugMode && saved) {
        debugPrint('[OneDayRepo] Added message: id=${newMessage.id} text="${text.trim()}"');
      }
      return saved;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OneDayRepo] add error: $e');
      }
      return false;
    }
  }

  /// 24時間経過したメッセージを削除（24hピッタリは残す）
  Future<int> cleanupExpired() async {
    try {
      final messages = await load();
      final now = DateTime.now().toUtc();
      final validMessages = messages.where((msg) {
        final diff = now.difference(msg.createdAt);
        return diff <= const Duration(hours: 24);
      }).toList();

      final deletedCount = messages.length - validMessages.length;
      if (deletedCount > 0) {
        await _save(validMessages);
        if (kDebugMode) {
          debugPrint('[OneDayRepo] Cleaned up $deletedCount expired messages');
        }
      }
      if (kDebugMode) {
        debugPrint('[OneDayRepo] cleanupExpired deleted=$deletedCount remain=${validMessages.length}');
      }
      return deletedCount;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OneDayRepo] cleanupExpired error: $e');
      }
      return 0;
    }
  }

  /// デバッグ用: 全メッセージのcreatedAtを過去にずらす（debugビルド限定）
  /// Releaseビルドでは no-op で false を返す
  Future<bool> debugShiftAllCreatedAt(Duration shift) {
    // Releaseビルドでは assert が無効化され、この関数は即座に false を返す
    assert(() {
      // Debugビルドでのみこの処理が存在することを保証
      return kDebugMode;
    }());
    // Releaseビルドでは常に false を返す（安全な no-op）
    if (!kDebugMode) {
      return Future.value(false);
    }
    return _debugShiftAllCreatedAtImpl(shift);
  }

  /// デバッグ用実装（debugビルドでのみ実行される）
  /// shift が負の値の場合、過去にずらす（例: -25時間 = 25時間前にずらす）
  Future<bool> _debugShiftAllCreatedAtImpl(Duration shift) async {
    try {
      final messages = await load();
      final shiftedMessages = messages.map((msg) {
        // shift が負の値（例: -25時間）の場合、過去にずらすため subtract(shift.abs()) を使用
        // shift が正の値の場合、未来にずらすため add(shift) を使用
        final newCreatedAt = shift.isNegative
            ? msg.createdAt.subtract(shift.abs())
            : msg.createdAt.add(shift);
        return OneDayMessage(
          id: msg.id,
          text: msg.text,
          createdAt: newCreatedAt,
        );
      }).toList();
      return await _save(shiftedMessages);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OneDayRepo] debugShiftAllCreatedAt error: $e');
      }
      return false;
    }
  }

  /// メッセージを保存
  Future<bool> _save(List<OneDayMessage> messages) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = messages.map((msg) => msg.toJson()).toList();
      final jsonString = jsonEncode(jsonList);
      return await prefs.setString(_key, jsonString);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OneDayRepo] _save error: $e');
      }
      return false;
    }
  }
}
