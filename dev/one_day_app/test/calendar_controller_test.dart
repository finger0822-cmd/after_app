import 'package:flutter_test/flutter_test.dart';
import 'package:after_app/features/calendar/calendar_controller.dart';
import 'package:after_app/data/message_repo.dart';
import 'package:after_app/data/message_model.dart';
import 'package:after_app/core/time.dart';
import 'package:uuid/uuid.dart';

void main() {
  group('CalendarController 未到達メッセージ取得テスト', () {
    test('loadMessagesForDay: openedAt==null, openOn==指定日のメッセージが取得される', () async {
      // Arrange
      final repo = TestMessageRepo();
      final targetDate = TimeUtils.addDays(TimeUtils.today(), 7);
      final controller = CalendarController(repo);
      
      // 未到達メッセージを作成
      final notArrivedMessage = Message.create(
        messageId: const Uuid().v4(),
        text: 'まだ届いていないメッセージ',
        openOn: targetDate,
        createdAt: TimeUtils.today(),
        openedAt: null, // まだ届いていない
      );
      await repo.create(notArrivedMessage);
      
      // Act
      await controller.loadMessagesForDay(targetDate);
      
      // Assert
      expect(controller.state.openedMessages.length, 1);
      expect(controller.state.openedMessages[0].messageId, notArrivedMessage.messageId);
      expect(controller.state.openedMessages[0].openedAt, isNull);
      expect(TimeUtils.isSameDay(controller.state.openedMessages[0].openOn, targetDate), true);
    });

    test('loadMessagesForDay: 開封済みメッセージも取得される', () async {
      // Arrange
      final repo = TestMessageRepo();
      final targetDate = TimeUtils.addDays(TimeUtils.today(), 7);
      final controller = CalendarController(repo);
      
      // 開封済みメッセージを作成
      final arrivedMessage = Message.create(
        messageId: const Uuid().v4(),
        text: '届いたメッセージ',
        openOn: targetDate,
        createdAt: TimeUtils.today(),
        openedAt: DateTime.now(), // 届いている
      );
      await repo.create(arrivedMessage);
      
      // Act
      await controller.loadMessagesForDay(targetDate);
      
      // Assert
      expect(controller.state.openedMessages.length, 1);
      expect(controller.state.openedMessages[0].messageId, arrivedMessage.messageId);
      expect(controller.state.openedMessages[0].openedAt, isNotNull);
    });

    test('loadMessagesForDay: 異なるopenOnのメッセージは取得されない', () async {
      // Arrange
      final repo = TestMessageRepo();
      final targetDate = TimeUtils.addDays(TimeUtils.today(), 7);
      final otherDate = TimeUtils.addDays(TimeUtils.today(), 14);
      final controller = CalendarController(repo);
      
      // 異なるopenOnのメッセージを作成
      final otherMessage = Message.create(
        messageId: const Uuid().v4(),
        text: '別の日のメッセージ',
        openOn: otherDate,
        createdAt: TimeUtils.today(),
        openedAt: null,
      );
      await repo.create(otherMessage);
      
      // Act
      await controller.loadMessagesForDay(targetDate);
      
      // Assert
      expect(controller.state.openedMessages.length, 0);
    });
  });
}

// テスト用のMessageRepo
class TestMessageRepo extends MessageRepo {
  final List<Message> _messages = [];

  @override
  Future<void> create(Message message) async {
    _messages.add(message);
  }

  @override
  Future<List<Message>> getMessagesByOpenOn(DateTime openOn) async {
    final targetDate = TimeUtils.toDateOnly(openOn);
    return _messages.where((msg) {
      final msgDate = TimeUtils.toDateOnly(msg.openOn);
      return TimeUtils.isSameDay(msgDate, targetDate);
    }).toList();
  }

  @override
  Future<List<Message>> getOpenedMessages() async {
    return _messages.where((msg) => msg.openedAt != null).toList();
  }

  @override
  Future<List<Message>> searchOpenedMessages(String query) async {
    final opened = await getOpenedMessages();
    if (query.isEmpty) return opened;
    final lowerQuery = query.toLowerCase();
    return opened.where((msg) => msg.text.toLowerCase().contains(lowerQuery)).toList();
  }

  @override
  Future<List<Message>> getSealedMessages() async {
    return _messages.where((msg) => msg.openedAt == null).toList();
  }

  @override
  Future<Message?> getById(String messageId) async {
    try {
      return _messages.firstWhere((msg) => msg.messageId == messageId);
    } catch (e) {
      return null;
    }
  }
}





