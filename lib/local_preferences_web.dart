import 'package:web/web.dart' as web;

class LocalPreferenceStore {
  const LocalPreferenceStore();

  Future<String?> getString(String key) async {
    return web.window.localStorage.getItem(key);
  }

  Future<bool?> getBool(String key) async {
    final value = web.window.localStorage.getItem(key);
    if (value == null) {
      return null;
    }
    return value == 'true';
  }

  Future<void> setString(String key, String value) async {
    web.window.localStorage.setItem(key, value);
  }

  Future<void> setBool(String key, bool value) async {
    web.window.localStorage.setItem(key, value.toString());
  }

  Future<void> remove(String key) async {
    web.window.localStorage.removeItem(key);
  }
}
