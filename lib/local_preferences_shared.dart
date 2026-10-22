import 'package:shared_preferences/shared_preferences.dart';

class LocalPreferenceStore {
  const LocalPreferenceStore();

  Future<String?> getString(String key) async {
    final preferences = await SharedPreferences.getInstance().timeout(
      const Duration(seconds: 2),
    );
    return preferences.getString(key);
  }

  Future<bool?> getBool(String key) async {
    final preferences = await SharedPreferences.getInstance().timeout(
      const Duration(seconds: 2),
    );
    return preferences.getBool(key);
  }

  Future<void> setString(String key, String value) async {
    final preferences = await SharedPreferences.getInstance().timeout(
      const Duration(seconds: 2),
    );
    await preferences.setString(key, value);
  }

  Future<void> setBool(String key, bool value) async {
    final preferences = await SharedPreferences.getInstance().timeout(
      const Duration(seconds: 2),
    );
    await preferences.setBool(key, value);
  }

  Future<void> remove(String key) async {
    final preferences = await SharedPreferences.getInstance().timeout(
      const Duration(seconds: 2),
    );
    await preferences.remove(key);
  }
}
