import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'domain/one_day_message.dart';
import 'data/one_day_repo.dart';
import 'features/one_day/one_day_page.dart';

/// One Day アプリのメインWidget
class OneDayApp extends StatelessWidget {
  const OneDayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'One Day',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const OneDayPage(),
    );
  }
}

/// One Day アプリのホームページ
class OneDayHomePage extends StatefulWidget {
  const OneDayHomePage({super.key});

  @override
  State<OneDayHomePage> createState() => _OneDayHomePageState();
}

class _OneDayHomePageState extends State<OneDayHomePage> with WidgetsBindingObserver {
  final _repo = OneDayRepo();
  final _textController = TextEditingController();
  List<OneDayMessage> _messages = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  /// 初期化（cleanup + load）
  Future<void> _init() async {
    if (kDebugMode) {
      debugPrint('[OneDayHomePage] init');
    }
    await _repo.cleanupExpired();
    await _loadMessages();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // アプリ復帰時に24時間経過したメッセージを削除
      _cleanupExpired();
    }
  }

  /// 24時間経過したメッセージを削除（復帰時）
  Future<void> _cleanupExpired() async {
    try {
      final deletedCount = await _repo.cleanupExpired();
      if (deletedCount > 0) {
        if (kDebugMode) {
          debugPrint('[OneDayHomePage] cleanup on resumed: $deletedCount');
        }
        await _loadMessages();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OneDayHomePage] cleanup error: $e');
      }
    }
  }

  /// メッセージ一覧を読み込み
  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);
    try {
      final messages = await _repo.load();
      setState(() {
        _messages = messages;
        _isLoading = false;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OneDayHomePage] load error: $e');
      }
      setState(() => _isLoading = false);
    }
  }

  /// メッセージを追加
  Future<void> _addMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      return;
    }

    final success = await _repo.add(text);
    if (success) {
      _textController.clear();
      await _loadMessages();
    }
  }

  /// デバッグ用: 全メッセージを25時間前にずらしてcleanup（debugビルド限定）
  /// Releaseビルドでは no-op
  Future<void> _debugShiftAndCleanup() async {
    // Releaseビルドでは assert が無効化され、この関数は即座に return する
    assert(() {
      // Debugビルドでのみこの処理が存在することを保証
      return kDebugMode;
    }());
    // Releaseビルドでは何もしない（安全な no-op）
    if (!kDebugMode) {
      return;
    }
    await _debugShiftAndCleanupImpl();
  }

  /// デバッグ用実装（debugビルドでのみ実行される）
  Future<void> _debugShiftAndCleanupImpl() async {
    try {
      debugPrint('[OneDayHomePage] Debug: Shifting all messages -25h');
      final shifted = await _repo.debugShiftAllCreatedAt(const Duration(hours: -25));
      if (shifted) {
        await _repo.cleanupExpired();
        await _loadMessages();
        debugPrint('[OneDayHomePage] Debug: Shift and cleanup completed');
      }
    } catch (e) {
      debugPrint('[OneDayHomePage] Debug shift error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('One Day'),
        actions: kDebugMode
            ? [
                IconButton(
                  icon: const Text('-25h', style: TextStyle(fontSize: 12)),
                  tooltip: 'Debug: Shift all messages -25h and cleanup',
                  onPressed: _debugShiftAndCleanup,
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          // 入力欄
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    decoration: const InputDecoration(
                      hintText: 'メッセージを入力...',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _addMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _isLoading ? null : _addMessage,
                  child: const Text('追加'),
                ),
              ],
            ),
          ),
          // メッセージ一覧
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(
                        child: Text(
                          'まだ何もありません',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          final nowUtc = DateTime.now().toUtc();
                          final diff = nowUtc.difference(message.createdAt);
                          final minutesAgo = diff.inMinutes;
                          final hoursAgo = diff.inHours;
                          
                          // 残り時間を計算（24時間 - 経過時間）
                          final remaining = const Duration(hours: 24) - diff;
                          final remainingHours = remaining.inHours;
                          final remainingMinutes = remaining.inMinutes % 60;
                          
                          // 表示テキスト：経過時間 + 残り時間
                          String timeText;
                          if (hoursAgo < 1) {
                            timeText = '$minutesAgo分前';
                          } else {
                            timeText = '$hoursAgo時間前';
                          }
                          
                          String remainingText;
                          if (remaining.isNegative) {
                            remainingText = '期限切れ';
                          } else if (remainingHours > 0) {
                            remainingText = '残り${remainingHours}時間';
                          } else {
                            remainingText = '残り${remainingMinutes}分';
                          }
                          
                          return ListTile(
                            title: Text(message.text),
                            subtitle: Text(
                              '$timeText ($remainingText)',
                              style: const TextStyle(fontSize: 12),
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
