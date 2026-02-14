import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/message_model.dart' as model;
import '../../data/message_repo.dart';
import '../../core/time.dart';
import '../../core/notification.dart';
import '../now/now_controller.dart';

final sealedControllerProvider = StateNotifierProvider<SealedController, SealedState>((ref) {
  return SealedController(ref.read(messageRepoProvider));
});

class SealedState {
  final List<model.Message> messages;
  final bool isLoading;

  SealedState({
    this.messages = const [],
    this.isLoading = false,
  });

  SealedState copyWith({
    List<model.Message>? messages,
    bool? isLoading,
  }) {
    return SealedState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class SealedController extends StateNotifier<SealedState> {
  final MessageRepo _repo;

  SealedController(this._repo) : super(SealedState()) {
    loadMessages();
  }

  Future<void> loadMessages() async {
    state = state.copyWith(isLoading: true);
    final messages = await _repo.getSealedMessages();
    state = state.copyWith(messages: messages, isLoading: false);
  }

  Future<bool> changeDate(String messageId, DateTime newDate) async {
    final message = await _repo.getById(messageId);
    if (message == null || message.openedAt != null || message.dateChangeUsed) {
      return false;
    }
    final original = message.openOn;
    message.openOn = DateTime(
      newDate.year,
      newDate.month,
      newDate.day,
      original.hour,
      original.minute,
      original.second,
      original.millisecond,
      original.microsecond,
    );
    message.dateChangeUsed = true;

    await NotificationService.cancelNotificationForMessage(message);
    await _repo.update(message);
    await NotificationService.scheduleNotificationForMessage(message);

    await loadMessages();
    return true;
  }

  Future<bool> deleteMessage(String messageId) async {
    try {
      final message = await _repo.getById(messageId);
      if (message == null) {
        debugPrint('[SealedController] deleteMessage: message not found: $messageId');
        return false;
      }
      
      if (message.openedAt != null) {
        debugPrint('[SealedController] deleteMessage: message already opened: $messageId');
        return false; // 開封済みは削除不可
      }

      // 通知のキャンセルでエラーが発生しても削除は続行
      try {
        await NotificationService.cancelNotificationForMessage(message);
      } catch (e) {
        debugPrint('[SealedController] deleteMessage: notification cancel failed: $e');
        // 通知のキャンセルに失敗しても削除は続行
      }
      
      final deleted = await _repo.delete(messageId);
      if (deleted) {
        debugPrint('[SealedController] deleteMessage: success: $messageId');
        await loadMessages();
        return true;
      } else {
        debugPrint('[SealedController] deleteMessage: delete failed: $messageId');
        return false;
      }
    } catch (e) {
      debugPrint('[SealedController] deleteMessage: exception: $e');
      return false;
    }
  }
}

