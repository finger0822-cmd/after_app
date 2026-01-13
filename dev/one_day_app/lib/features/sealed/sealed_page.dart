import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../data/message_model.dart' as model;
import 'sealed_controller.dart';

class SealedPage extends ConsumerStatefulWidget {
  const SealedPage({super.key});

  @override
  ConsumerState<SealedPage> createState() => _SealedPageState();
}

class _SealedPageState extends ConsumerState<SealedPage> {
  Future<void> _changeDate(model.Message message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('封印日を変更'),
        content: const Text('封印日を変更します。この記録は、これ以上日付を変更できません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('変更'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final today = DateTime.now();
    final firstDate = DateTime(today.year, today.month, today.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: message.openOn,
      firstDate: firstDate,
      lastDate: DateTime(today.year + 10, 12, 31),
    );

    if (picked != null && mounted) {
      await ref.read(sealedControllerProvider.notifier).changeDate(message.messageId, picked);
    }
  }

  Future<void> _deleteMessage(model.Message message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('削除'),
        content: const Text('この記録を削除します。元に戻すことはできません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await ref.read(sealedControllerProvider.notifier).deleteMessage(message.messageId);
      if (!success && mounted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('削除に失敗しました')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sealedControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('封印中'),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : state.messages.isEmpty
              ? const Center(child: Text('封印中の記録がありません'))
              : ListView.builder(
                  itemCount: state.messages.length,
                  itemBuilder: (context, index) {
                    final message = state.messages[index];
                    return ListTile(
                      title: Text('Open on ${FormatUtils.formatDate(message.openOn)}'),
                      subtitle: Text(
                        'Created ${FormatUtils.formatDate(message.createdAt)} • Sealed',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!message.dateChangeUsed)
                            TextButton(
                              onPressed: () => _changeDate(message),
                              child: const Text('Change date (1 left)', style: TextStyle(fontSize: 12)),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deleteMessage(message),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

