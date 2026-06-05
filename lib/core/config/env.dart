import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Typed access to runtime config. Loaded once in main() via [Env.load].
class Env {
  Env._();

  static Future<void> load() => dotenv.load(fileName: '.env');

  static String get supabaseUrl => _require('SUPABASE_URL');
  static String get supabaseAnonKey => _require('SUPABASE_ANON_KEY');

  static String _require(String key) {
    final v = dotenv.maybeGet(key);
    if (v == null || v.isEmpty) {
      throw StateError(
        'Missing "$key" in .env — copy .env.example to .env and fill it in.',
      );
    }
    return v;
  }
}
