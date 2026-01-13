import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/format.dart';
import 'now_controller.dart';

class NowPage extends ConsumerStatefulWidget {
  const NowPage({super.key});

  @override
  ConsumerState<NowPage> createState() => _NowPageState();
}

class _NowPageState extends ConsumerState<NowPage> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
    _textController.addListener(() {
      setState(() {}); // テキスト変更時にボタンの有効/無効を更新
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final controller = ref.read(nowControllerProvider.notifier);
    final currentDate = ref.read(nowControllerProvider).selectedDate;
    final today = DateTime.now();
    final firstDate = DateTime(today.year, today.month, today.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: firstDate,
      lastDate: DateTime(today.year + 10, 12, 31),
    );

    if (picked != null) {
      controller.updateDate(picked);
    }
  }

  Future<void> _handleSubmit() async {
    final text = _textController.text;
    if (text.trim().isEmpty) return;

    final controller = ref.read(nowControllerProvider.notifier);
    await controller.submit(text);

    final state = ref.read(nowControllerProvider);
    if (state.submitStatus == SubmitStatus.success && mounted) {
      _textController.clear();
      _focusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(nowControllerProvider);
    final selectedDate = state.selectedDate;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Now'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock),
            onPressed: () {
              Navigator.of(context).pushNamed('/sealed');
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.of(context).pushNamed('/after');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              TextField(
                controller: _textController,
                focusNode: _focusNode,
                maxLines: 1,
                maxLength: 140,
                decoration: const InputDecoration(
                  hintText: 'メッセージを入力',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _handleSubmit(),
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: () => _selectDate(context),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Text('Open on '),
                      Text(
                        FormatUtils.formatDate(selectedDate),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      const Icon(Icons.calendar_today, size: 20),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: (state.isSubmitting || _textController.text.trim().isEmpty)
                    ? null
                    : _handleSubmit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: state.isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send to After'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

