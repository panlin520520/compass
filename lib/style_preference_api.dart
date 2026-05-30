import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';
import 'auth_service.dart';

/// 样式偏好：本地 SharedPreferences 为主，登录后同步服务端。
///
/// 小米等机型冷启动时网络可能较慢或失败，仅依赖服务端会导致样式丢失。
class StylePreferenceApi {
  static String _localStorageKey(String page) => 'style_preferences_local_$page';

  static Future<Map<String, String>> _loadLocal(String page) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localStorageKey(page));
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return {};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> _persistLocalMap(
    String page,
    Map<String, String> map,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localStorageKey(page), json.encode(map));
  }

  static Future<void> _saveLocal({
    required String page,
    required String prefKey,
    required String prefValue,
  }) async {
    final map = await _loadLocal(page);
    map[prefKey] = prefValue;
    await _persistLocalMap(page, map);
  }

  static Future<Map<String, String>> _loadRemote(String page) async {
    if (!AuthService.isLoggedIn) return {};
    final user = AuthService.currentUser.value;
    if (user == null) return {};

    try {
      final resp = await http.get(
        Uri.parse(
          '$kApiBaseUrl/cp/stylePreference/list'
          '?userId=${user.userId}&page=$page',
        ),
        headers: {
          'Authorization': 'Bearer ${user.token}',
        },
      );
      if (resp.statusCode != 200) return {};
      final data = json.decode(resp.body);
      if (data is! Map || (data['code'] != 200 && data['code'] != '200')) {
        return {};
      }
      final list = (data['data'] as List?) ?? [];
      final Map<String, String> map = {};
      for (final item in list) {
        final m = item is Map<String, dynamic>
            ? item
            : Map<String, dynamic>.from(item as Map);
        final key = (m['prefKey'] ?? '').toString();
        final value = (m['prefValue'] ?? '').toString();
        if (key.isNotEmpty) {
          map[key] = value;
        }
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveRemote({
    required String page,
    required String prefKey,
    required String prefValue,
  }) async {
    if (!AuthService.isLoggedIn) return;
    final user = AuthService.currentUser.value;
    if (user == null) return;

    final body = {
      'userId': user.userId,
      'page': page,
      'prefKey': prefKey,
      'prefValue': prefValue,
    };

    try {
      await http.post(
        Uri.parse('$kApiBaseUrl/cp/stylePreference'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer ${user.token}',
        },
        body: json.encode(body),
      );
    } catch (_) {
      // 服务端保存失败不影响本地已写入的缓存
    }
  }

  /// 加载指定 page 下的样式偏好。优先读本地，登录后再尝试合并服务端。
  static Future<Map<String, String>> loadPreferences(String page) async {
    final local = await _loadLocal(page);

    if (!AuthService.isLoggedIn) return local;

    final remote = await _loadRemote(page);
    if (remote.isEmpty) return local;

    final merged = <String, String>{...local, ...remote};
    await _persistLocalMap(page, merged);
    return merged;
  }

  /// 保存样式偏好：先写本地（确保小米等机型杀进程后仍能恢复），再同步服务端。
  static Future<void> savePreference({
    required String page,
    required String prefKey,
    required String prefValue,
  }) async {
    await _saveLocal(
      page: page,
      prefKey: prefKey,
      prefValue: prefValue,
    );
    await _saveRemote(
      page: page,
      prefKey: prefKey,
      prefValue: prefValue,
    );
  }
}
