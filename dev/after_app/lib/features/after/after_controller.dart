import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/message_model.dart' as model;
import '../../data/message_repo.dart';
import '../now/now_controller.dart';

final afterControllerProvider = StateNotifierProvider<AfterController, AfterState>((ref) {
  return AfterController(ref.read(messageRepoProvider));
});

class AfterState {
  final List<model.Message> messages;
  final String searchQuery;
  final bool isLoading;

  AfterState({
    this.messages = const [],
    this.searchQuery = '',
    this.isLoading = false,
  });

  AfterState copyWith({
    List<model.Message>? messages,
    String? searchQuery,
    bool? isLoading,
  }) {
    return AfterState(
      messages: messages ?? this.messages,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AfterController extends StateNotifier<AfterState> {
  final MessageRepo _repo;

  AfterController(this._repo) : super(AfterState()) {
    loadMessages();
  }

  Future<void> loadMessages() async {
    state = state.copyWith(isLoading: true);
    final messages = await _repo.getOpenedMessages();
    state = state.copyWith(messages: messages, isLoading: false);
  }

  void updateSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  Future<void> search() async {
    state = state.copyWith(isLoading: true);
    final messages = await _repo.searchOpenedMessages(state.searchQuery);
    state = state.copyWith(messages: messages, isLoading: false);
  }

  Future<void> deleteMessage(String messageId) async {
    await _repo.delete(messageId);
    await loadMessages();
  }
}

