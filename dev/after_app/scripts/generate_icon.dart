import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// アイコン生成スクリプト
/// 
/// 使用方法:
///   dart run scripts/generate_icon.dart
/// 
/// または、Flutterプロジェクトのルートから:
///   flutter run -d windows scripts/generate_icon.dart
/// 
/// ただし、dartコマンドで直接実行する場合は、Flutterのパスを通す必要があります。
/// 推奨: Flutterプロジェクト内で `flutter run` を使用するか、
/// または `dart --enable-asserts scripts/generate_icon.dart` を実行

void main() async {
  // Flutter bindingを初期化（必須）
  WidgetsFlutterBinding.ensureInitialized();

  // Afterアイコン（地平線）を生成
  await generateAfterIcon();

  print('アイコン生成完了: after_icon.png');
}

/// Afterアイコン（地平線）を生成
/// 
/// キャンバスの下から38.2%（黄金比）の位置に水平線を描画
Future<void> generateAfterIcon() async {
  const size = 1024.0;
  const backgroundColor = Color(0xFFFFFFFF); // 純白
  const lineColor = Color(0xFF1A1A1A); // 墨色
  const lineWidth = 1.75; // 1.5px〜2.0pxの間（視認性を確保）

  // 黄金比: 下から38.2% = 上から61.8%
  const goldenRatio = 0.618;
  final lineY = size * goldenRatio;

  // PictureRecorderを作成
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  // 背景を描画
  final backgroundPaint = Paint()..color = backgroundColor;
  canvas.drawRect(Rect.fromLTWH(0, 0, size, size), backgroundPaint);

  // 水平線を描画
  final linePaint = Paint()
    ..color = lineColor
    ..strokeWidth = lineWidth
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.square; // 端を四角く（端から端まで）

  // 端から端まで水平線を描画
  canvas.drawLine(
    Offset(0, lineY),
    Offset(size, lineY),
    linePaint,
  );

  // Pictureを完成させる
  final picture = recorder.endRecording();

  // PNGに変換
  final image = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

  if (byteData == null) {
    throw Exception('画像の生成に失敗しました');
  }

  // ファイルに保存（プロジェクトルートに保存）
  final currentDir = Directory.current;
  final file = File('${currentDir.path}/after_icon.png');
  await file.writeAsBytes(byteData.buffer.asUint8List());
  
  print('保存先: ${file.absolute.path}');
}

/// 他のアイコン生成用のヘルパー関数
/// 
/// この関数を拡張して、垂直線や点などの他のアイコンも生成できます。
/// 
/// 例:
///   - 垂直線: 左から38.2%の位置に垂直線
///   - 点: 中心に点
///   - 複数線: 複数の水平線や垂直線の組み合わせ
/// 
/// 使用例:
///   await generateIcon(
///     filename: 'vertical_icon.png',
///     drawFunction: (canvas, size) {
///       final lineX = size * 0.382;
///       canvas.drawLine(
///         Offset(lineX, 0),
///         Offset(lineX, size),
///         Paint()..color = Color(0xFF1A1A1A)..strokeWidth = 1.75,
///       );
///     },
///   );
Future<void> generateIcon({
  required String filename,
  required void Function(Canvas canvas, double size) drawFunction,
  Color backgroundColor = const Color(0xFFFFFFFF),
  double size = 1024.0,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  // 背景を描画
  final backgroundPaint = Paint()..color = backgroundColor;
  canvas.drawRect(Rect.fromLTWH(0, 0, size, size), backgroundPaint);

  // カスタム描画関数を実行
  drawFunction(canvas, size);

  // Pictureを完成させる
  final picture = recorder.endRecording();

  // PNGに変換
  final image = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

  if (byteData == null) {
    throw Exception('画像の生成に失敗しました');
  }

  // ファイルに保存（プロジェクトルートに保存）
  final currentDir = Directory.current;
  final file = File('${currentDir.path}/$filename');
  await file.writeAsBytes(byteData.buffer.asUint8List());
  
  print('保存先: ${file.absolute.path}');
}
