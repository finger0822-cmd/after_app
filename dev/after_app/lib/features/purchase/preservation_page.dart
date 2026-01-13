import 'package:flutter/material.dart';

class PreservationPage extends StatefulWidget {
  const PreservationPage({super.key});

  @override
  State<PreservationPage> createState() => _PreservationPageState();
}

class _PreservationPageState extends State<PreservationPage>
    with SingleTickerProviderStateMixin {
  bool _isProcessing = false;
  bool _showMessage = false; // メッセージ表示フラグ
  late AnimationController _overlayController;
  late AnimationController _messageController; // メッセージ用の別アニメーション
  late Animation<double> _fadeAnimation;
  late Animation<double> _messageFadeAnimation;

  @override
  void initState() {
    super.initState();
    _overlayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000), // 3秒かけて暗転
    );
    _messageController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000), // メッセージのフェードイン
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _overlayController,
        curve: Curves.easeInOut,
      ),
    );
    _messageFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _messageController,
        curve: Curves.easeIn,
      ),
    );
  }

  @override
  void dispose() {
    _overlayController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9), // 静かなオフホワイト
      body: SafeArea(
        child: Stack(
          children: [
            // メインコンテンツ
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text(
                    'この場所を、このままに。',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 60),
                  const Text(
                    '月額400円の場所代は、あなたの言葉を誰にも触れさせず、\n'
                    '時間の中に安全に保管し続けるための誠実な維持費です。\n\n'
                    'ここには、あなたを追い立てる通知も、\n'
                    '誰かからの評価も、広告も、分析も存在しません。\n\n'
                    '何も書かない月があっても、この聖域は守られます。\n'
                    '価値は機能ではなく、流れる時間の中にあります。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w200,
                      height: 2.2,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 80),
                  // 購入ボタン
                  OutlinedButton(
                    onPressed: _isProcessing ? null : () => _handlePurchase(context),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.black12),
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(0),
                      ),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(
                            '場所を維持する（月額400円）',
                            style: TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.w300,
                              letterSpacing: 1,
                            ),
                          ),
                  ),
                  const SizedBox(height: 100),
                  // リーガル系（極めて薄く）
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _linkText('リストア'),
                      _divider(),
                      _linkText('利用規約'),
                      _divider(),
                      _linkText('プライバシー'),
                    ],
                  ),
                ],
              ),
            ),
            // 閉じるボタン
            Positioned(
              top: 20,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, size: 20, color: Colors.black26),
                onPressed: _isProcessing ? null : () => Navigator.pop(context),
              ),
            ),
            // 決済完了後の「儀式」オーバーレイ
            if (_isProcessing)
              AnimatedBuilder(
                animation: Listenable.merge([_fadeAnimation, _messageFadeAnimation]),
                builder: (context, child) {
                  return Container(
                    color: Color.lerp(
                      Colors.transparent,
                      const Color(0xFF1A1A1A), // 深い墨色
                      _fadeAnimation.value,
                    ),
                    child: Center(
                      child: _showMessage
                          ? Opacity(
                              opacity: _messageFadeAnimation.value,
                              child: const Text(
                                '承りました。\n時間は、止まらずに流れていきます。',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w200,
                                  color: Colors.white,
                                  height: 2.0,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _linkText(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 10, color: Colors.black26),
    );
  }

  Widget _divider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8),
      child: Text('|', style: TextStyle(fontSize: 10, color: Colors.black12)),
    );
  }

  Future<void> _handlePurchase(BuildContext context) async {
    // 処理中フラグを立てる
    setState(() {
      _isProcessing = true;
    });

    try {
      // TODO: 実際の決済ロジックをここに実装
      // 例: await PurchaseService.purchaseSubscription();
      
      // 決済処理をシミュレート（実際の実装では削除）
      await Future.delayed(const Duration(milliseconds: 500));

      // 決済完了後の「儀式」を開始
      await _showSuccessRitual(context);
    } catch (e) {
      // エラー時は処理中フラグを解除
      setState(() {
        _isProcessing = false;
      });
      // エラーハンドリング（必要に応じて実装）
      debugPrint('[PreservationPage] Purchase error: $e');
    }
  }

  /// 決済完了後の「儀式」的な演出
  /// 1. 暗転（3秒かけて深い墨色に染まる）
  /// 2. 暗転完了後、メッセージが浮かび上がる
  /// 3. メッセージが表示された状態で2秒待機
  /// 4. フェードアウトしてメイン画面に戻る
  Future<void> _showSuccessRitual(BuildContext context) async {
    // 1. 暗転開始（3秒かけて）
    await _overlayController.forward();

    // 2. 暗転完了後、メッセージを表示
    if (mounted) {
      setState(() {
        _showMessage = true;
      });
      await _messageController.forward();
    }

    // 3. メッセージが表示された状態で2秒待機
    await Future.delayed(const Duration(milliseconds: 2000));

    // 4. メッセージをフェードアウト
    await _messageController.reverse();

    // 5. 暗転もフェードアウト（1秒）
    await _overlayController.reverse();

    // 6. メイン画面に戻る
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}
