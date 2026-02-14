import 'package:isar/isar.dart';
import 'db.dart';
import 'message_model.dart';
import '../core/time.dart';
import '../core/crash_logger.dart';

class MessageRepo {
  Future<Isar> get _isar => Database.instance;

  Future<void> create(Message message, {int? sessionId}) async {
    final isar = await _isar;
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
    final allSealed = await isar.messages
        .filter()
        .openedAtIsNull()
        .findAll();
    return allSealed.where((msg) => msg.openOn.isAfter(now)).toList();
  }

  Future<void> openMessagesDueToday() async {
    final isar = await _isar;
    final now = DateTime.now();
    final allSealed = await isar.messages
        .filter()
        .openedAtIsNull()
        .findAll();
    
    final messages = allSealed.where((msg) {
      return !msg.openOn.isAfter(now);
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
}
