import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// テキストフレーズとその配置情報
class TextPhrase {
  final String text;
  final double x; // 円の中心からの相対座標（-1.0〜1.0）
  final double y; // 円の中心からの相対座標（-1.0〜1.0）
  final double rotation; // 回転角度（ラジアン）
  final double fontSize; // フォントサイズ

  TextPhrase({
    required this.text,
    required this.x,
    required this.y,
    required this.rotation,
    required this.fontSize,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'x': x,
        'y': y,
        'rotation': rotation,
        'fontSize': fontSize,
      };

  factory TextPhrase.fromJson(Map<String, dynamic> json) => TextPhrase(
        text: json['text'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        rotation: (json['rotation'] as num).toDouble(),
        fontSize: (json['fontSize'] as num).toDouble(),
      );
}

/// 今日を閉じる装置用のリポジトリ（午前4時リセット）
class OneDayCloseRepo {
  static const String _keyPhrases = 'one_day_close_phrases';
  static const String _keyLastSaveTime = 'one_day_close_last_save_time';

  /// 最後に言葉を置いた時刻を取得
  Future<DateTime?> getLastSaveTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_keyLastSaveTime);
      if (timestamp == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OneDayCloseRepo] getLastSaveTime error: $e');
      }
      return null;
    }
  }

  /// 午前4時をまたいでいるかチェック
  /// 前回の保存時刻から現在時刻までの間に「午前4時」をまたいでいる場合、trueを返す
  Future<bool> hasCrossed4AM() async {
    try {
      final lastSaveTime = await getLastSaveTime();
      if (lastSaveTime == null) return false;

      final now = DateTime.now();

      // 前回の保存時刻の「午前4時基準の日付」を計算
      // 午前4時より前なら前日、午前4時以降なら当日として扱う
      final last4AMDate = lastSaveTime.hour < 4
          ? DateTime(lastSaveTime.year, lastSaveTime.month, lastSaveTime.day - 1, 4)
          : DateTime(lastSaveTime.year, lastSaveTime.month, lastSaveTime.day, 4);

      // 現在時刻の「午前4時基準の日付」を計算
      final now4AMDate = now.hour < 4
          ? DateTime(now.year, now.month, now.day - 1, 4)
          : DateTime(now.year, now.month, now.day, 4);

      // 日付が異なれば、午前4時をまたいでいる
      return last4AMDate.year != now4AMDate.year ||
          last4AMDate.month != now4AMDate.month ||
          last4AMDate.day != now4AMDate.day;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OneDayCloseRepo] hasCrossed4AM error: $e');
      }
      return false;
    }
  }

  /// テキストフレーズリストを読み込む（午前4時をまたいでいたら自動的にクリア）
  Future<List<TextPhrase>> loadPhrases() async {
    try {
      // 午前4時をまたいでいたら自動的にクリア
      if (await hasCrossed4AM()) {
        await clear();
        return [];
      }

      final prefs = await SharedPreferences.getInstance();
      final phrasesJson = prefs.getString(_keyPhrases);
      if (phrasesJson == null) return [];

      final List<dynamic> decoded = json.decode(phrasesJson);
      return decoded.map((json) => TextPhrase.fromJson(json)).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OneDayCloseRepo] loadPhrases error: $e');
      }
      return [];
    }
  }

  /// テキストフレーズを追加
  Future<bool> addPhrase(TextPhrase phrase) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 既存のフレーズを読み込む
      final existingPhrases = await loadPhrases();

      // 新しいフレーズを追加
      final updatedPhrases = [...existingPhrases, phrase];

      // JSONに変換して保存
      final phrasesJson = json.encode(
        updatedPhrases.map((p) => p.toJson()).toList(),
      );
      await prefs.setString(_keyPhrases, phrasesJson);

      // 最後に言葉を置いた時刻を記録
      await prefs.setInt(
        _keyLastSaveTime,
        DateTime.now().millisecondsSinceEpoch,
      );

      if (kDebugMode) {
        debugPrint(
          '[OneDayCloseRepo] addPhrase: total=${updatedPhrases.length}, lastSaveTime=${DateTime.now()}',
        );
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OneDayCloseRepo] addPhrase error: $e');
      }
      return false;
    }
  }

  /// すべてをクリア（午前4時をまたいだ時など）
  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyPhrases);
      await prefs.remove(_keyLastSaveTime);

      if (kDebugMode) {
        debugPrint('[OneDayCloseRepo] clear: all data removed');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OneDayCloseRepo] clear error: $e');
      }
    }
  }

  /// 合計文字数を取得
  Future<int> getTotalCharacterCount() async {
    try {
      final phrases = await loadPhrases();
      int total = 0;
      for (final phrase in phrases) {
        total += phrase.text.length;
      }
      return total;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OneDayCloseRepo] getTotalCharacterCount error: $e');
      }
      return 0;
    }
  }
}
