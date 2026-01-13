import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/message_model.dart' as model;
import '../../data/message_repo.dart';
import '../now/now_controller.dart';

final calendarControllerProvider = StateNotifierProvider<CalendarController, CalendarState>((ref) {
  return CalendarController(ref.read(messageRepoProvider));
});

class CalendarState {
  final DateTime selectedDay;
  final List<model.Message> openedMessages;
  final String searchQuery;
  final bool isSearching;
  final bool isLoading;
  final bool isAbsorbing; // 吸い込み中フラグ（当日セルのテキスト表示を抑止）

  CalendarState({
    required this.selectedDay,
    this.openedMessages = const [],
    this.searchQuery = '',
    this.isSearching = false,
    this.isLoading = false,
    this.isAbsorbing = false,
  });

  CalendarState copyWith({
    DateTime? selectedDay,
    List<model.Message>? openedMessages,
    String? searchQuery,
    bool? isSearching,
    bool? isLoading,
    bool? isAbsorbing,
  }) {
    return CalendarState(
      selectedDay: selectedDay ?? this.selectedDay,
      openedMessages: openedMessages ?? this.openedMessages,
      searchQuery: searchQuery ?? this.searchQuery,
      isSearching: isSearching ?? this.isSearching,
      isLoading: isLoading ?? this.isLoading,
      isAbsorbing: isAbsorbing ?? this.isAbsorbing,
    );
  }
}

class CalendarController extends StateNotifier<CalendarState> {
  final MessageRepo _repo;

  CalendarController(this._repo) : super(CalendarState(selectedDay: DateTime.now())) {
    loadMessagesForDay(state.selectedDay);
  }

  void selectDay(DateTime day) {
    state = state.copyWith(selectedDay: day);
    loadMessagesForDay(day);
  }

  Future<void> loadMessagesForDay(DateTime day) async {
    if (state.isSearching) return; // 検索中は更新しない

    state = state.copyWith(isLoading: true);
    
    // 選択日のopenOnに一致するメッセージを取得（開封済み/未開封問わず）
    final dayMessages = await _repo.getMessagesByOpenOn(day);

    state = state.copyWith(openedMessages: dayMessages, isLoading: false);
  }

  void startSearch() {
    state = state.copyWith(isSearching: true, searchQuery: '');
  }

  void cancelSearch() {
    state = state.copyWith(isSearching: false, searchQuery: '');
    loadMessagesForDay(state.selectedDay);
  }

  void updateSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  Future<void> performSearch() async {
    if (state.searchQuery.isEmpty) {
      cancelSearch();
      return;
    }

    state = state.copyWith(isLoading: true);
    final messages = await _repo.searchOpenedMessages(state.searchQuery);
    state = state.copyWith(openedMessages: messages, isLoading: false);
  }

  Future<void> refresh() async {
    if (state.isSearching) {
      await performSearch();
    } else {
      await loadMessagesForDay(state.selectedDay);
    }
  }

  /// 吸い込み開始時に呼ばれる
  void startAbsorbing() {
    state = state.copyWith(isAbsorbing: true);
  }

  /// 吸い込み完了時に呼ばれる
  void stopAbsorbing() {
    state = state.copyWith(isAbsorbing: false);
  }
}

