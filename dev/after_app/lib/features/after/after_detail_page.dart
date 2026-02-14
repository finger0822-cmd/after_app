import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import '../../data/message_model.dart' as model;
import 'after_controller.dart';

class AfterDetailPage extends ConsumerStatefulWidget {
  final model.Message message;

  const AfterDetailPage({super.key, required this.message});

  @override
  ConsumerState<AfterDetailPage> createState() => _AfterDetailPageState();
}

class _AfterDetailPageState extends ConsumerState<AfterDetailPage> {
  bool _decided = false;

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final ok = await showDialog<bool>(
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

    if (ok == true) {
      await ref
          .read(afterControllerProvider.notifier)
          .deleteMessage(widget.message.messageId);
      _decided = true;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('削除しました')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(afterControllerProvider.notifier);
    final isProtected = ref.watch(afterControllerProvider).protectedIds.contains(
          widget.message.messageId,
        );

    return WillPopScope(
      onWillPop: () async {
        if (_decided) {
          return true;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('保護か削除を選択してください')),
        );
        return false;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: const Text('記録'),
          automaticallyImplyLeading: false,
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '送った日 ${FormatUtils.formatDate(widget.message.createdAt)}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 16),
              Text(
                widget.message.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w300,
                  fontSize: 18,
                  height: 1.8,
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final ok = await controller.toggleProtection(
                          widget.message.messageId,
                        );
                        if (!ok) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('保護は20件までです')),
                            );
                          }
                          return;
                        }
                        _decided = true;
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isProtected ? '保護を解除しました' : '保護しました',
                              ),
                            ),
                          );
                          Navigator.of(context).pop();
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white54),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(isProtected ? '保護を解除' : '保護する'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _confirmDelete(context, ref),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent),
                        foregroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('削除'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
