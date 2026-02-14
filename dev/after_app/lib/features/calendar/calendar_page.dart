import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';
import '../../core/format.dart';
import '../../core/time.dart';
import 'calendar_controller.dart';
import 'now_sheet.dart';
import 'sealed_sheet.dart';

class CalendarPage extends ConsumerStatefulWidget {
  const CalendarPage({super.key});

  @override
  ConsumerState<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends ConsumerState<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  final _searchController = TextEditingController();
  final GlobalKey _todayCellKey = GlobalKey();
  Rect? _cachedTodayCellRect; // 今日セルの座標をキャッシュ
  String? _lastHeroTag; // 最後に送信されたHeroのtag
  // String? _lastHeroText; // 最後に送信されたテキスト（将来使用する可能性があるためコメントアウト）

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openNowSheet(DateTime selectedDay) async {
    final today = TimeUtils.today();
    final initialOpenOn = selectedDay.isBefore(today) ? today : selectedDay;
    
    // overlayContextを保存（NowSheetでOverlay取得に使用）
    final overlayContext = context;
    
    // 必ず_focusedDayを今日に設定してから待つ（既に今日の月でも再設定）
    final todayMonth = DateTime(today.year, today.month);
    final focusedMonth = DateTime(_focusedDay.year, _focusedDay.month);
    final needsUpdate = todayMonth.year != focusedMonth.year || todayMonth.month != focusedMonth.month;
    
    if (needsUpdate) {
      print('[CalendarPage] _openNowSheet: focusedDay is not today month, updating...');
      debugPrint('[CalendarPage] _openNowSheet: focusedDay is not today month, updating...');
    } else {
      print('[CalendarPage] _openNowSheet: focusedDay is already today month');
      debugPrint('[CalendarPage] _openNowSheet: focusedDay is already today month');
    }
    
    // 必ず_focusedDayを今日に設定（再設定でも問題ない）
    setState(() {
      _focusedDay = today;
    });
    
    // TableCalendarが再ビルドされるまで待つ（複数フレーム、より長く待つ）
    await SchedulerBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 200));
    await SchedulerBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 200));
    await SchedulerBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 200));
    await SchedulerBinding.instance.endOfFrame;
    await Future.delayed(const Duration(milliseconds: 200));
    
    print('[CalendarPage] _openNowSheet: after setState, waiting for todayBuilder...');
    debugPrint('[CalendarPage] _openNowSheet: after setState, waiting for todayBuilder...');
    
    // キャッシュされた座標を使用（なければ取得を試みる）
    Rect? todayCellRect = _cachedTodayCellRect;
    
    print('[CalendarPage] _openNowSheet: cached todayCellRect=$todayCellRect');
    debugPrint('[CalendarPage] _openNowSheet: cached todayCellRect=$todayCellRect');
    
    // キャッシュがない場合、複数フレーム待ってから取得を試みる（最大10回、待機時間を長く）
    if (todayCellRect == null) {
      print('[CalendarPage] trying to get todayCellRect with retries');
      debugPrint('[CalendarPage] trying to get todayCellRect with retries');
      
      // まず現在のフレームが完了するまで待つ
      await SchedulerBinding.instance.endOfFrame;
      await Future.delayed(const Duration(milliseconds: 100));
      
      for (int i = 0; i < 10; i++) {
        // 各試行の前にフレームが完了するまで待つ
        await SchedulerBinding.instance.endOfFrame;
        await Future.delayed(const Duration(milliseconds: 100));
        
        if (_todayCellKey.currentContext != null) {
          final box = _todayCellKey.currentContext!.findRenderObject() as RenderBox?;
          if (box != null && box.hasSize) {
            final topLeft = box.localToGlobal(Offset.zero);
            todayCellRect = topLeft & box.size;
            _cachedTodayCellRect = todayCellRect; // キャッシュにも保存
            print('[CalendarPage] todayCellRect obtained on attempt ${i + 1}: $todayCellRect');
            debugPrint('[CalendarPage] todayCellRect obtained on attempt ${i + 1}: $todayCellRect');
            break;
          }
        }
        print('[CalendarPage] attempt ${i + 1}: todayCellKey.currentContext=${_todayCellKey.currentContext != null ? "not null" : "null"}');
        debugPrint('[CalendarPage] attempt ${i + 1}: todayCellKey.currentContext=${_todayCellKey.currentContext != null ? "not null" : "null"}');
      }
    }
    
    print('[CalendarPage] todayCellRect to pass: $todayCellRect');
    debugPrint('[CalendarPage] todayCellRect to pass: $todayCellRect');
    
    // 毎回新しいsessionIdを生成（状態リセット用）
    final sessionId = DateTime.now().microsecondsSinceEpoch;
    
    // Hero受け皿を準備するコールバック
    void onPrepareAbsorb(String heroTag, String previewText) {
      setState(() {
        _lastHeroTag = heroTag;
        // _lastHeroText = previewText; // 将来使用する可能性があるためコメントアウト
      });
      debugPrint('[CalendarPage] onPrepareAbsorb called, tag=$heroTag');
      debugPrint('[CalendarPage] today cell contains hero tag=$heroTag');
      debugPrint('[CalendarPage] hero target dot mounted (tag=$heroTag)');
    }
    
    final result = await showGeneralDialog<SubmitResult>(
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
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: NowSheet(
                  initialOpenOn: initialOpenOn,
                  sessionId: sessionId,
                  todayCellKey: _todayCellKey,
                  todayCellRect: todayCellRect, // 事前に取得した座標を渡す
                  overlayContext: overlayContext,
                  absorbAnimator: null,
                  fallbackRunner: null,
                  onPrepareAbsorb: onPrepareAbsorb,
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (_, anim, __, child) {
        final fade = CurvedAnimation(parent: anim, curve: Curves.easeOut);
        return FadeTransition(
          opacity: fade,
          child: child,
        );
      },
      transitionDuration: const Duration(milliseconds: 160),
    );

    // 成功時はカレンダーを更新するだけ（afterの思想：静か・非強制）
    // 吸い込みアニメーションで既に「手放した」感覚を伝えている
    if (result == SubmitResult.success) {
      ref.read(calendarControllerProvider.notifier).refresh();
    }
  }

  void _openSealedSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const SealedSheet(),
    ).then((_) {
      // シートが閉じたらカレンダーを更新
      ref.read(calendarControllerProvider.notifier).refresh();
    });
  }

  void _toggleSearch() {
    final controller = ref.read(calendarControllerProvider.notifier);
    final state = ref.read(calendarControllerProvider);
    
    if (state.isSearching) {
      controller.cancelSearch();
      _searchController.clear();
    } else {
      controller.startSearch();
    }
  }

  void _performSearch() {
    final controller = ref.read(calendarControllerProvider.notifier);
    final query = _searchController.text;
    controller.updateSearchQuery(query);
    controller.performSearch();
  }

  String _getEmptyMessage(DateTime selectedDay) {
    final today = TimeUtils.today();
    final sel = TimeUtils.toDateOnly(selectedDay);
    
    if (sel.isAfter(today)) {
      return 'この日はまだ来ていません';
    } else if (TimeUtils.isSameDay(sel, today)) {
      return '右下の＋ か 今日をクリックして書く';
    } else {
      return 'この日は記録がありません';
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(calendarControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: state.isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '検索',
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _performSearch(),
              )
            : const Text('After'),
        leading: state.isSearching
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _toggleSearch,
              )
            : IconButton(
                icon: const Icon(Icons.access_time),
                tooltip: 'まだ届いていない記録',
                onPressed: _openSealedSheet,
              ),
        actions: [
          if (!state.isSearching)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _toggleSearch,
            ),
        ],
      ),
      body: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // 横幅に合わせて正方形セルを作る（広すぎるWindows対策で最大幅を制限）
              final maxW = constraints.maxWidth.clamp(0.0, 520.0);
              final cell = (maxW / 7.0).floorToDouble(); // 正方形
              final calendarW = cell * 7;

              // TableCalendarがビルドされた後に今日セルの座標を更新（複数フレーム待つ）
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Future.delayed(const Duration(milliseconds: 200), () async {
                  // 複数フレーム待ってから座標を取得
                  for (int i = 0; i < 5; i++) {
                    await SchedulerBinding.instance.endOfFrame;
                    await Future.delayed(const Duration(milliseconds: 50));
                    
                    if (mounted && _todayCellKey.currentContext != null) {
                      final box = _todayCellKey.currentContext!.findRenderObject() as RenderBox?;
                      if (box != null && box.hasSize) {
                        final topLeft = box.localToGlobal(Offset.zero);
                        _cachedTodayCellRect = topLeft & box.size;
                        print('[CalendarPage] build: todayCellRect updated on attempt ${i + 1}: $_cachedTodayCellRect');
                        debugPrint('[CalendarPage] build: todayCellRect updated on attempt ${i + 1}: $_cachedTodayCellRect');
                        break;
                      }
                    }
                    print('[CalendarPage] build: attempt ${i + 1}: todayCellKey.currentContext=${_todayCellKey.currentContext != null ? "not null" : "null"}');
                    debugPrint('[CalendarPage] build: attempt ${i + 1}: todayCellKey.currentContext=${_todayCellKey.currentContext != null ? "not null" : "null"}');
                  }
                });
              });

              return Center(
                child: SizedBox(
                  width: calendarW,
                  child: TableCalendar(
                    firstDay: DateTime.utc(2020, 1, 1),
                    lastDay: DateTime.utc(2030, 12, 31),
                    focusedDay: _focusedDay,

                    // 正方形
                    rowHeight: cell,
                    daysOfWeekHeight: 28,

                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: false,
                      leftChevronVisible: true,
                      rightChevronVisible: true,
                      headerPadding: EdgeInsets.symmetric(vertical: 8),
                      titleTextStyle: TextStyle(fontSize: 0), // titleは使わない（自前で描く）
                    ),

                    calendarStyle: const CalendarStyle(
                      outsideDaysVisible: true,
                      isTodayHighlighted: false, // 今日ハイライトは自前で制御
                    ),

                    selectedDayPredicate: (day) => isSameDay(day, state.selectedDay),

                    enabledDayPredicate: (day) {
                      final today = TimeUtils.today();
                      final d = TimeUtils.toDateOnly(day);
                      return !d.isAfter(today); // 未来日を無効化
                    },

                    onDaySelected: (selectedDay, focusedDay) {
                      final today = TimeUtils.today();
                      final sel = TimeUtils.toDateOnly(selectedDay);

                      // 未来日は完全無効
                      if (sel.isAfter(today)) return;

                      setState(() {
                        _focusedDay = focusedDay;
                      });

                      ref.read(calendarControllerProvider.notifier).selectDay(sel);

                      // 書き込みできるのは今日だけ
                      if (TimeUtils.isSameDay(sel, today)) {
                        final defaultOpenOn = TimeUtils.addDays(today, 7);
                        _openNowSheet(defaultOpenOn);
                      }
                    },

                    calendarFormat: CalendarFormat.month,
                    startingDayOfWeek: StartingDayOfWeek.monday,

                    calendarBuilders: CalendarBuilders(
                      // ヘッダー（左：月、中央：英語月名、右：年）
                      headerTitleBuilder: (context, day) {
                        final monthNum = DateFormat('M').format(day);        // "10"
                        final monthName = DateFormat('MMMM').format(day);    // "October"
                        final year = DateFormat('y').format(day);            // "2025"

                        return Row(
                          children: [
                            Text(
                              monthNum,
                              style: const TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w300,
                                height: 1.0,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              monthName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              year,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w300,
                              ),
                            ),
                          ],
                        );
                      },

                      // 曜日行（SUN 赤 / SAT 青 っぽく）
                      dowBuilder: (context, day) {
                        final text = DateFormat('EEE').format(day).toUpperCase(); // SUN MON...
                        final isSun = day.weekday == DateTime.sunday;
                        final isSat = day.weekday == DateTime.saturday;

                        Color? c;
                        if (isSun) c = const Color(0xFFE53935);
                        if (isSat) c = const Color(0xFF1E88E5);

                        return Center(
                          child: Text(
                            text,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: c ?? Colors.black87,
                            ),
                          ),
                        );
                      },

                      // 日セル（罫線＋左上寄せ＋週末色）
                      defaultBuilder: (context, day, focusedDay) {
                        final today = TimeUtils.today();
                        final d = TimeUtils.toDateOnly(day);
                        final isFuture = d.isAfter(today);
                        final isToday = TimeUtils.isSameDay(d, today);
                        
                        if (isToday) {
                          print('[CalendarPage] defaultBuilder: today cell found, day=$day');
                          debugPrint('[CalendarPage] defaultBuilder: today cell found, day=$day');
                          
                          // 今日の日付の場合、キーを付与（todayBuilderが呼ばれない場合の代替手段）
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            Future.delayed(const Duration(milliseconds: 100), () {
                              if (mounted && _todayCellKey.currentContext != null) {
                                final box = _todayCellKey.currentContext!.findRenderObject() as RenderBox?;
                                if (box != null && box.hasSize) {
                                  final topLeft = box.localToGlobal(Offset.zero);
                                  _cachedTodayCellRect = topLeft & box.size;
                                  print('[CalendarPage] defaultBuilder: todayCellRect cached: $_cachedTodayCellRect');
                                  debugPrint('[CalendarPage] defaultBuilder: todayCellRect cached: $_cachedTodayCellRect');
                                }
                              }
                            });
                          });
                        }
                        
                        return Opacity(
                          opacity: isFuture ? 0.35 : 1.0,
                          child: _gridDayCell(
                            context,
                            day,
                            isSelected: false,
                            isToday: false,
                            key: isToday ? _todayCellKey : null, // 今日の日付の場合、キーを付与
                          ),
                        );
                      },
                      outsideBuilder: (context, day, focusedDay) {
                        return _gridDayCell(
                          context,
                          day,
                          isSelected: false,
                          isToday: false,
                          isOutside: true,
                        );
                      },
                      todayBuilder: (context, day, focusedDay) {
                        // 今日を「編集できる日」として強調
                        final isSelected = isSameDay(day, state.selectedDay);
                        
                        print('[CalendarPage] todayBuilder called for day=$day');
                        debugPrint('[CalendarPage] todayBuilder called for day=$day');
                        
                        // このWidgetがビルドされた後に座標を取得（複数フレーム待つ）
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          Future.delayed(const Duration(milliseconds: 50), () {
                            if (mounted && _todayCellKey.currentContext != null) {
                              final box = _todayCellKey.currentContext!.findRenderObject() as RenderBox?;
                              if (box != null && box.hasSize) {
                                final topLeft = box.localToGlobal(Offset.zero);
                                _cachedTodayCellRect = topLeft & box.size;
                                print('[CalendarPage] todayBuilder: todayCellRect cached: $_cachedTodayCellRect');
                                debugPrint('[CalendarPage] todayBuilder: todayCellRect cached: $_cachedTodayCellRect');
                              } else {
                                print('[CalendarPage] todayBuilder: box is null or has no size');
                                debugPrint('[CalendarPage] todayBuilder: box is null or has no size');
                              }
                            } else {
                              print('[CalendarPage] todayBuilder: context is null or not mounted');
                              debugPrint('[CalendarPage] todayBuilder: context is null or not mounted');
                            }
                          });
                        });
                        
                        return Tooltip(
                          message: '今日のメッセージを書く',
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: _gridDayCell(
                              context,
                              day,
                              isSelected: isSelected,
                              isToday: true,
                              key: _todayCellKey, // Containerに直接キーを付与
                            ),
                          ),
                        );
                      },
                      selectedBuilder: (context, day, focusedDay) {
                        // 選択は背景を薄く塗る（正方形を維持）
                        final today = TimeUtils.today();
                        final d = TimeUtils.toDateOnly(day);
                        final isToday = TimeUtils.isSameDay(d, today);
                        
                        if (isToday) {
                          print('[CalendarPage] selectedBuilder: today cell found, day=$day');
                          debugPrint('[CalendarPage] selectedBuilder: today cell found, day=$day');
                          
                          // 今日の日付の場合、キーを付与
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            Future.delayed(const Duration(milliseconds: 100), () {
                              if (mounted && _todayCellKey.currentContext != null) {
                                final box = _todayCellKey.currentContext!.findRenderObject() as RenderBox?;
                                if (box != null && box.hasSize) {
                                  final topLeft = box.localToGlobal(Offset.zero);
                                  _cachedTodayCellRect = topLeft & box.size;
                                  print('[CalendarPage] selectedBuilder: todayCellRect cached: $_cachedTodayCellRect');
                                  debugPrint('[CalendarPage] selectedBuilder: todayCellRect cached: $_cachedTodayCellRect');
                                }
                              }
                            });
                          });
                        }
                        
                        return _gridDayCell(
                          context,
                          day,
                          isSelected: true,
                          isToday: isToday,
                          key: isToday ? _todayCellKey : null, // 今日の日付の場合、キーを付与
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : state.openedMessages.isEmpty
                    ? Center(
                        child: Text(
                          state.isSearching
                              ? '検索結果がありません'
                              : _getEmptyMessage(state.selectedDay),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: state.openedMessages.length,
                        itemBuilder: (context, index) {
                          final message = state.openedMessages[index];
                          final isArrived = message.openedAt != null;
                          return ListTile(
                            title: Text('届く日 ${FormatUtils.formatDate(message.openOn)}'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (isArrived)
                                  Text(
                                    '書いた日 ${FormatUtils.formatDate(message.createdAt)}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey.shade600,
                                    ),
                                  )
                                else
                                  Text(
                                    'まだ届いていない',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                const SizedBox(height: 4),
                                if (isArrived)
                                  Text(
                                    message.text,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      // 過去の言葉は少しだけ淡く、細く。
                                      fontWeight: FontWeight.w200,
                                      color: Colors.black54,
                                      fontSize: 16,
                                      height: 1.8,
                                    ),
                                  )
                                else
                                  Text(
                                    '（本文は届くまで表示されません）',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Colors.grey.shade500,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final today = TimeUtils.today();
          final defaultOpenOn = TimeUtils.addDays(today, 7);
          _openNowSheet(defaultOpenOn);
        },
        icon: const Icon(Icons.add),
        label: const Text('今日を書く'),
      ),
    );
  }

  // --- ヘルパー：日セルの描画 ---
  // Hero吸い込み先の点（静か）
  Widget _AbsorbDot() {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _gridDayCell(
    BuildContext context,
    DateTime day, {
    required bool isSelected,
    required bool isToday,
    bool isOutside = false,
    Key? key,
  }) {
    final isSun = day.weekday == DateTime.sunday;
    final isSat = day.weekday == DateTime.saturday;

    Color textColor = Colors.black87;
    if (isOutside) textColor = Colors.black26;
    if (!isOutside && isSun) textColor = const Color(0xFFE53935);
    if (!isOutside && isSat) textColor = const Color(0xFF1E88E5);

    final borderColor = Colors.black26;

    return MouseRegion(
      onEnter: isToday ? (_) {} : null,
      onExit: isToday ? (_) {} : null,
      child: Container(
        key: key,
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: 1),
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
              : isToday
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.05)
                  : Colors.transparent,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 日付数字：左上
            Positioned(
              left: 6,
              top: 6,
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
            ),

            // 今日：枠＋鉛筆アイコン
            if (isToday) ...[
              // 枠線
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
              // 鉛筆アイコン（右上）
              Positioned(
                right: 4,
                top: 4,
                child: Icon(
                  Icons.edit,
                  size: 12,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                ),
              ),
              // Heroの受け皿（中央）- 常に配置（nullの場合はshrink）
              Positioned.fill(
                child: Center(
                  child: _lastHeroTag != null
                      ? Hero(
                          tag: _lastHeroTag!,
                          child: _AbsorbDot(),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

