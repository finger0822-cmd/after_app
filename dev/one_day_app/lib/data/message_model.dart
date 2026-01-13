import 'package:isar/isar.dart';

part 'message_model.g.dart';

@collection
class Message {
  Id id = Isar.autoIncrement;

  @Index()
  late String messageId;

  late String text;

  @Index()
  late DateTime openOn;

  DateTime? openedAt;

  @Index()
  late DateTime createdAt;

  late bool dateChangeUsed;

  Message();

  Message.create({
    required this.messageId,
    required this.text,
    required this.openOn,
    this.openedAt,
    required this.createdAt,
    this.dateChangeUsed = false,
  });
}

