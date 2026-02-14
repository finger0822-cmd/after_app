import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  final Set<String> protectedIds;

  AfterState({
    this.messages = const [],
    this.searchQuery = '',
    this.isLoading = false,
    this.protectedIds = const {},
  });

  AfterState copyWith({
    List<model.Message>? messages,
    String? searchQuery,
    bool? isLoading,
    Set<String>? protectedIds,
  }) {
    return AfterState(
      messages: messages ?? this.messages,
      searchQuery: searchQuery ?? this.searchQuery,
      isLoading: isLoading ?? this.isLoading,
      protectedIds: protectedIds ?? this.protectedIds,
    );
  }
}

class AfterController extends StateNotifier<AfterState> {
  static const _protectedKey = 'after_protected_message_ids';
  final MessageRepo _repo;

  AfterController(this._repo) : super(AfterState()) {
    loadMessages();
    _loadProtectedIds();
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

  bool isProtected(String messageId) {
    return state.protectedIds.contains(messageId);
  }

  Future<bool> toggleProtection(String messageId) async {
    final prefs = await SharedPreferences.getInstance();
    final next = {...state.protectedIds};
    if (!next.add(messageId)) {
      next.remove(messageId);
    } else if (next.length > 20) {
      return false;
    }
    await prefs.setStringList(_protectedKey, next.toList());
    state = state.copyWith(protectedIds: next);
    return true;
  }

  Future<void> _loadProtectedIds() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_protectedKey) ?? const <String>[];
    state = state.copyWith(protectedIds: ids.toSet());
  }

  Future<void> deleteMessage(String messageId) async {
    await _repo.delete(messageId);
    if (state.protectedIds.contains(messageId)) {
      final prefs = await SharedPreferences.getInstance();
      final next = {...state.protectedIds}..remove(messageId);
      await prefs.setStringList(_protectedKey, next.toList());
      state = state.copyWith(protectedIds: next);
    }
    await loadMessages();
  }
}

