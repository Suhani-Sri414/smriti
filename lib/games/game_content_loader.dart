import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'cognitive_game.dart';

/// Loads the item catalogue games draw from.
///
/// Still the mock JSON bundled with the app: `get_patient_content` carries
/// people, medications and routine items, but no market goods, so there is
/// nothing pulled to build Market Basket items from yet.
Future<GameContent> loadMockGameContent() async {
  final raw = await rootBundle.loadString(
    'assets/mock_content/mock_content.json',
    cache: false,
  );
  return GameContent.fromJson(jsonDecode(raw) as Map<String, Object?>);
}
