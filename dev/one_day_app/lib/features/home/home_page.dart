import 'package:flutter/material.dart';
import '../../core/time.dart';
import '../../data/message_repo.dart';
import '../calendar/now_sheet.dart';
import 'delivered_page.dart';

/// ホーム画面（思想提示専用）
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _hasCheckedDelivered = false; // 二重実行防止フラグ
  final _absorbTargetKey = GlobalKey(); // 吸い込み先アンカー用のGlobalKey

  @override
  void initState() {
    super.initState();
    // ビルド完了後に届いたメッセージをチェック
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndShowDelivered();
    });
  }

  Future<void> _checkAndShowDelivered() async {
    // 二重実行防止
    if (_hasCheckedDelivered || !mounted) return;
    _hasCheckedDelivered = true;

    final repo = MessageRepo();
    final sealed = await repo.getSealedMessages();
    final today = TimeUtils.today();
    
    // 届いたメッセージ = openOn <= today かつ openedAt == null
    final hasDelivered = sealed.any((msg) {
      final msgDate = TimeUtils.toDateOnly(msg.openOn);
      return !msgDate.isAfter(today);
    });

    if (hasDelivered && mounted) {
      // showGeneralDialogでDeliveredPageを上に被せる
      showGeneralDialog(
        context: context,
        barrierDismissible: true, // タップで閉じられる
        barrierLabel: 'delivered',
        barrierColor: Colors.black54,
        pageBuilder: (_, __, ___) {
          return const DeliveredPage();
        },
        transitionBuilder: (_, anim, __, child) {
          final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
          return FadeTransition(
            opacity: fade,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 200),
      );
    }
  }

  Future<void> _openNowSheet(BuildContext context) async {
    final today = TimeUtils.today();
    final defaultOpenOn = TimeUtils.addDays(today, 7);
    final sessionId = DateTime.now().microsecondsSinceEpoch;
    
    await showGeneralDialog<SubmitResult>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'now',
      barrierColor: Colors.black54,
      pageBuilder: (_, __, ___) {
        return SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Material(
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: NowSheet(
                  initialOpenOn: defaultOpenOn,
                  sessionId: sessionId,
                  todayCellKey: null,
                  todayCellRect: null,
                  targetKey: _absorbTargetKey, // HomePageの吸い込み先アンカーを渡す
                  overlayContext: context,
                  absorbAnimator: null,
                  fallbackRunner: null,
                  onPrepareAbsorb: null,
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim, __, child) {
        final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        final scale = Tween<double>(begin: 0.98, end: 1.0).animate(fade);
        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
      transitionDuration: const Duration(milliseconds: 160),
    );
    
    // 成功時は何も表示しない（afterの思想：静か・非強制）
    // 吸い込みアニメーションで既に「手放した」感覚を伝えている
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 固定テキスト1
              Text(
                '今の気持ちを、',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w300,
                  height: 1.8,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '未来の自分にだけ預ける',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w300,
                  height: 1.8,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              
              // 固定テキスト2
              Text(
                '書いた気持ちは、',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey.shade700,
                  height: 1.8,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'すぐには読めません',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey.shade700,
                  height: 1.8,
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 64),
              
              // ボタンは1つだけ
              FilledButton(
                onPressed: () => _openNowSheet(context),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                ),
                child: const Text('今の気持ちを書く'),
              ),
              
              // 吸い込み先アンカー（Opacity(0)で非表示、SizedBox(16,16)でRectを安定させる）
              Opacity(
                opacity: 0,
                child: SizedBox(
                  key: _absorbTargetKey,
                  width: 16,
                  height: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
