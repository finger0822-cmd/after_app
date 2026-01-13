import 'package:isar/isar.dart';
import 'db.dart';
import 'message_model.dart';
import '../core/time.dart';
import '../core/crash_logger.dart';

class MessageRepo {
  Future<Isar> get _isar => Database.instance;

  Future<void> create(Message message, {int? sessionId}) async {
    final isar = await _isar;
    // openOnをdateOnlyで正規化して保存
    message.openOn = TimeUtils.toDateOnly(message.openOn);
    await isar.writeTxn(() => isar.messages.put(message));
    // 監査用: DB保存後のログ（実害確認用）
    final auditSessionId = sessionId ?? DateTime.now().microsecondsSinceEpoch;
    CrashLogger.logInfo('[MessageRepo] SAVED id=${message.id} messageId=${message.messageId} createdAt=${message.createdAt.toIso8601String()} sessionId=$auditSessionId');
  }

  Future<void> update(Message message) async {
    final isar = await _isar;
    await isar.writeTxn(() => isar.messages.put(message));
  }

  Future<bool> delete(String messageId) async {
    try {
      final isar = await _isar;
      final message = await isar.messages.filter().messageIdEqualTo(messageId).findFirst();
      if (message != null) {
        await isar.writeTxn(() => isar.messages.delete(message.id));
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<List<Message>> getOpenedMessages() async {
    final isar = await _isar;
    return await isar.messages
        .filter()
        .openedAtIsNotNull()
        .sortByOpenedAtDesc()
        .findAll();
  }

  Future<List<Message>> searchOpenedMessages(String query) async {
    final isar = await _isar;
    final allOpened = await isar.messages
        .filter()
        .openedAtIsNotNull()
        .findAll();
    
    if (query.isEmpty) {
      return allOpened..sort((a, b) => (b.openedAt ?? b.createdAt).compareTo(a.openedAt ?? a.createdAt));
    }

    final lowerQuery = query.toLowerCase();
    return allOpened
        .where((msg) => msg.text.toLowerCase().contains(lowerQuery))
        .toList()
      ..sort((a, b) => (b.openedAt ?? b.createdAt).compareTo(a.openedAt ?? a.createdAt));
  }

  Future<List<Message>> getSealedMessages() async {
    final isar = await _isar;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return await isar.messages
        .filter()
        .openedAtIsNull()
        .openOnGreaterThan(today.subtract(const Duration(days: 1)))
        .findAll();
  }

  Future<void> openMessagesDueToday() async {
    final isar = await _isar;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final allSealed = await isar.messages
        .filter()
        .openedAtIsNull()
        .findAll();
    
    final messages = allSealed.where((msg) {
      final msgDate = DateTime(msg.openOn.year, msg.openOn.month, msg.openOn.day);
      return msgDate.isAtSameMomentAs(today) || (msgDate.isAfter(today) && msgDate.isBefore(tomorrow));
    }).toList();

    if (messages.isEmpty) return;

    await isar.writeTxn(() async {
      for (final message in messages) {
        message.openedAt = DateTime.now();
        await isar.messages.put(message);
      }
    });
  }

  Future<Message?> getById(String messageId) async {
    final isar = await _isar;
    return await isar.messages.filter().messageIdEqualTo(messageId).findFirst();
  }

  /// 指定日のopenOnに一致するメッセージを取得（開封済み/未開封問わず）
  Future<List<Message>> getMessagesByOpenOn(DateTime openOn) async {
    final isar = await _isar;
    // openOnをdateOnlyで正規化
    final targetDate = TimeUtils.toDateOnly(openOn);
    final nextDay = targetDate.add(const Duration(days: 1));
    
    // openOnが指定日と一致するメッセージを取得
    final allMessages = await isar.messages
        .filter()
        .openOnGreaterThan(targetDate.subtract(const Duration(seconds: 1)))
        .openOnLessThan(nextDay)
        .findAll();
    
    // さらに日付でフィルタ（Isarのクエリだけでは完全一致が難しいため）
    return allMessages.where((msg) {
      final msgDate = DateTime(msg.openOn.year, msg.openOn.month, msg.openOn.day);
      return msgDate.year == targetDate.year &&
          msgDate.month == targetDate.month &&
          msgDate.day == targetDate.day;
    }).toList();
  }

  /// 24時間以上経過したメッセージを削除（one day アプリの自動消去機能）
  Future<int> deleteMessagesOlderThan24Hours() async {
    try {
      final isar = await _isar;
      final now = DateTime.now();
      final cutoffTime = now.subtract(const Duration(hours: 24));
      
      // 24時間以上経過したメッセージを取得
      final expiredMessages = await isar.messages
          .filter()
          .createdAtLessThan(cutoffTime)
          .findAll();
      
      if (expiredMessages.isEmpty) {
        CrashLogger.logDebug('[MessageRepo] No expired messages to delete');
        return 0;
      }
      
      final count = expiredMessages.length;
      await isar.writeTxn(() async {
        for (final message in expiredMessages) {
          await isar.messages.delete(message.id);
        }
      });
      
      CrashLogger.logInfo('[MessageRepo] Deleted $count expired messages (older than 24 hours)');
      return count;
    } catch (e, stack) {
      CrashLogger.logException(e, stack, context: 'deleteMessagesOlderThan24Hours');
      return 0;
    }
  }

  /// 24時間以内のメッセージのみ取得（one day アプリ用）
  Future<List<Message>> getMessagesWithin24Hours() async {
    final isar = await _isar;
    final now = DateTime.now();
    final cutoffTime = now.subtract(const Duration(hours: 24));
    
    return await isar.messages
        .filter()
        .createdAtGreaterThan(cutoffTime)
        .sortByCreatedAtDesc()
        .findAll();
  }
}
