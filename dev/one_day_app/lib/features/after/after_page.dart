import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import 'after_controller.dart';

class AfterPage extends ConsumerStatefulWidget {
  const AfterPage({super.key});

  @override
  ConsumerState<AfterPage> createState() => _AfterPageState();
}

class _AfterPageState extends ConsumerState<AfterPage> {
  final _searchController = TextEditingController();
  bool _isSearching = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchController.clear();
        ref.read(afterControllerProvider.notifier).updateSearchQuery('');
        ref.read(afterControllerProvider.notifier).loadMessages();
      }
    });
  }

  void _performSearch() {
    final query = _searchController.text;
    ref.read(afterControllerProvider.notifier).updateSearchQuery(query);
    ref.read(afterControllerProvider.notifier).search();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(afterControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('After'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isSearching)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '検索',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _performSearch,
                  ),
                ),
                onSubmitted: (_) => _performSearch(),
              ),
            ),
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : state.messages.isEmpty
                    ? const Center(child: Text('記録がありません'))
                    : ListView.builder(
                        itemCount: state.messages.length,
                        itemBuilder: (context, index) {
                          final message = state.messages[index];
                          final date = message.openedAt ?? message.createdAt;
                          return ListTile(
                            title: Text(FormatUtils.formatDate(date)),
                            subtitle: Text(message.text),
                            isThreeLine: false,
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

