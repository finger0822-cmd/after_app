import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/message_model.dart';
import '../../data/message_repo.dart';
import '../../core/time.dart';
import '../../core/notification.dart';
import '../../core/crash_logger.dart';

final messageRepoProvider = Provider<MessageRepo>((ref) => MessageRepo());

final nowControllerProvider = StateNotifierProvider<NowController, NowState>((ref) {
  return NowController(ref.read(messageRepoProvider));
});

enum SubmitStatus {
  idle,
  submitting,
  success,
  failure,
}

class NowState {
  final DateTime selectedDate;
  final SubmitStatus submitStatus;
  final String? errorMessage;

  NowState({
    required this.selectedDate,
    this.submitStatus = SubmitStatus.idle,
    this.errorMessage,
  });

  bool get isSubmitting => submitStatus == SubmitStatus.submitting;

  NowState copyWith({
    DateTime? selectedDate,
    SubmitStatus? submitStatus,
    String? errorMessage,
  }) {
    return NowState(
      selectedDate: selectedDate ?? this.selectedDate,
      submitStatus: submitStatus ?? this.submitStatus,
      errorMessage: errorMessage,
    );
  }
}

class NowController extends StateNotifier<NowState> {
  final MessageRepo _repo;
  final _uuid = const Uuid();

  NowController(this._repo) : super(
    NowState(
      // デフォルトを7日から30日に変更。
      // 「一巡した未来」に届けるための思想的な設定。
      selectedDate: TimeUtils.addDays(TimeUtils.today(), 30)
    )
  );

  void updateDate(DateTime date) {
    state = state.copyWith(selectedDate: date);
  }

  Future<void> submit(String text, {int? sessionId}) async {
    // 監査用: sessionIdをログに含める
    final auditSessionId = sessionId ?? DateTime.now().microsecondsSinceEpoch;
    
    if (text.trim().isEmpty) {
      CrashLogger.logDebug('[NowController] submit: 開始 sessionId=$auditSessionId → 失敗（空文字）');
      state = state.copyWith(
        submitStatus: SubmitStatus.failure,
        errorMessage: 'メッセージを入力してください',
      );
      return;
    }
    if (text.length > 140) {
      CrashLogger.logDebug('[NowController] submit: 開始 sessionId=$auditSessionId → 失敗（文字数超過）');
      state = state.copyWith(
        submitStatus: SubmitStatus.failure,
        errorMessage: 'メッセージは140文字以内で入力してください',
      );
      return;
    }

    CrashLogger.logDebug('[NowController] submit: 開始 sessionId=$auditSessionId');
    state = state.copyWith(
      submitStatus: SubmitStatus.submitting,
      errorMessage: null,
    );

    try {
      final message = Message.create(
        messageId: _uuid.v4(),
        text: text.trim(),
        openOn: state.selectedDate,
        createdAt: DateTime.now(),
      );

      await _repo.create(message, sessionId: auditSessionId);
      try {
        await NotificationService.scheduleNotificationForMessage(message);
      } catch (e) {
        CrashLogger.logDebug('[NowController] notification schedule error: $e');
        // 通知のスケジュール失敗は保存成功を妨げない
      }

      CrashLogger.logDebug('[NowController] submit: 成功 sessionId=$auditSessionId');
      state = state.copyWith(
        submitStatus: SubmitStatus.success,
        errorMessage: null,
      );
    } catch (e) {
      CrashLogger.logDebug('[NowController] submit: 失敗 sessionId=$auditSessionId - $e');
      state = state.copyWith(
        submitStatus: SubmitStatus.failure,
        errorMessage: '保存できませんでした',
      );
    }
  }

  void resetStatus() {
    state = state.copyWith(
      submitStatus: SubmitStatus.idle,
      errorMessage: null,
    );
  }
}

