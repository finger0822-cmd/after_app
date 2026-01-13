import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'one_day_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  if (kDebugMode) {
    debugPrint('[OneDayApp] main ok');
  }
  runApp(const OneDayApp());
}
