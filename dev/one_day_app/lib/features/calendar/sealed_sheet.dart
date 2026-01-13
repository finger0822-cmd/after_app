import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../data/message_model.dart' as model;
import '../sealed/sealed_controller.dart';

class SealedSheet extends ConsumerStatefulWidget {
  const SealedSheet({super.key});

  @override
  ConsumerState<SealedSheet> createState() => _SealedSheetState();
}

class _SealedSheetState extends ConsumerState<SealedSheet> {
  Future<void> _changeDate(model.Message message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('届く日を変更'),
        content: const Text('届く日を変更します。この記録は、これ以上日付を変更できません。'),
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

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade600,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Text(
                  'まだ届いていない記録',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : state.messages.isEmpty
                    ? const Center(child: Text('まだ届いていない記録がありません'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: state.messages.length,
                        itemBuilder: (context, index) {
                          final message = state.messages[index];
                          return ListTile(
                            title: Text('届く日 ${FormatUtils.formatDate(message.openOn)}'),
                            subtitle: Text(
                              '書いた日 ${FormatUtils.formatDate(message.createdAt)} • まだ届いていない',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!message.dateChangeUsed)
                                  TextButton(
                                    onPressed: () => _changeDate(message),
                                    child: const Text('届く日を変更 (1回まで)', style: TextStyle(fontSize: 12)),
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
          ),
        ],
      ),
    );
  }
}

