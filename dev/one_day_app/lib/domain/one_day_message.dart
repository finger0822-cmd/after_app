/// One Day メッセージモデル
class OneDayMessage {
  final String id;
  final String text;
  final DateTime createdAt;

  OneDayMessage({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  /// JSON から作成
  factory OneDayMessage.fromJson(Map<String, dynamic> json) {
    return OneDayMessage(
      id: json['id'] as String,
      text: json['text'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    );
  }

  /// JSON に変換（UTCで保存）
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }
}
