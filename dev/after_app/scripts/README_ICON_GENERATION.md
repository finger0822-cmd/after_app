# アイコン生成スクリプト

## 概要

`generate_icon.dart` は、ミニマルアプリシリーズのアイコンを生成するためのスクリプトです。

## 実行方法

### 方法1: Flutterプロジェクト内で実行（推奨）

プロジェクトルート（`after_app/`）から実行:

```bash
cd after_app
flutter run -d windows -t scripts/generate_icon.dart
```

または、macOS/Linuxの場合:

```bash
cd after_app
flutter run -d macos -t scripts/generate_icon.dart
```

### 方法2: Dartコマンドで実行（Flutter SDKが必要）

```bash
cd after_app
dart --enable-asserts scripts/generate_icon.dart
```

## 生成されるファイル

- `after_icon.png` - Afterアプリのアイコン（地平線）
  - サイズ: 1024x1024px
  - 背景: 純白 (#FFFFFF)
  - 線: 墨色 (#1A1A1A)、1.75px
  - 位置: 下から38.2%（黄金比）の位置に水平線

## カスタマイズ方法

### 他のアイコンを生成する場合

`generateIcon` 関数を使用して、カスタム描画関数を定義できます。

例: 垂直線のアイコン

```dart
await generateIcon(
  filename: 'vertical_icon.png',
  drawFunction: (canvas, size) {
    final lineX = size * 0.382; // 左から38.2%の位置
    final linePaint = Paint()
      ..color = Color(0xFF1A1A1A)
      ..strokeWidth = 1.75
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    canvas.drawLine(
      Offset(lineX, 0),
      Offset(lineX, size),
      linePaint,
    );
  },
);
```

例: 中心に点

```dart
await generateIcon(
  filename: 'dot_icon.png',
  drawFunction: (canvas, size) {
    final center = Offset(size / 2, size / 2);
    final dotPaint = Paint()
      ..color = Color(0xFF1A1A1A)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 8.0, dotPaint); // 半径8pxの点
  },
);
```

## 設計仕様

- **サイズ**: 1024x1024px（アプリアイコン標準）
- **背景色**: 純白 (#FFFFFF)
- **線の色**: 墨色 (#1A1A1A)
- **線の太さ**: 1.5px〜2.0px（視認性を確保）
- **黄金比**: 38.2%（下から）または 61.8%（上から）

## 注意事項

- このスクリプトはFlutter SDKが必要です（`dart:ui`パッケージを使用）
- 生成されたPNGファイルはプロジェクトルートに保存されます
- 既存のファイルは上書きされます
