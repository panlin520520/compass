import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_config.dart';

class AuthUser {
  AuthUser({
    required this.userId,
    required this.token,
    required this.nickName,
    required this.avatar,
    this.phoneNumber = '',
  });

  final int userId;
  final String token;
  final String nickName;
  final String avatar;
  final String phoneNumber;

  String get displayPhone {
    if (phoneNumber.isNotEmpty) return phoneNumber;
    if (RegExp(r'^1\d{10}$').hasMatch(nickName)) return nickName;
    return '';
  }
}

/// 登录态（token + 基本用户信息）管理
class AuthService {
  static const _kToken = 'cp_token';
  static const _kUserId = 'cp_user_id';
  static const _kNickName = 'cp_nick_name';
  static const _kAvatar = 'cp_avatar';
  static const _kPhoneNumber = 'cp_phone_number';

  static final ValueNotifier<AuthUser?> currentUser = ValueNotifier<AuthUser?>(null);

  static bool get isLoggedIn =>
      currentUser.value != null && currentUser.value!.token.isNotEmpty;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kToken) ?? '';
    if (token.isEmpty) {
      currentUser.value = null;
      return;
    }
    final userId = prefs.getInt(_kUserId) ?? 0;
    final nick = prefs.getString(_kNickName) ?? '';
    final avatar = prefs.getString(_kAvatar) ?? '';
    final phone = prefs.getString(_kPhoneNumber) ?? '';
    currentUser.value = AuthUser(
      userId: userId,
      token: token,
      nickName: nick,
      avatar: avatar,
      phoneNumber: phone,
    );
  }

  static Future<void> saveLogin({
    required int userId,
    required String token,
    required String nickName,
    required String avatar,
    String phoneNumber = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kUserId, userId);
    await prefs.setString(_kToken, token);
    await prefs.setString(_kNickName, nickName);
    await prefs.setString(_kAvatar, avatar);
    await prefs.setString(_kPhoneNumber, phoneNumber);
    currentUser.value = AuthUser(
      userId: userId,
      token: token,
      nickName: nickName,
      avatar: avatar,
      phoneNumber: phoneNumber,
    );
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kUserId);
    await prefs.remove(_kNickName);
    await prefs.remove(_kAvatar);
    await prefs.remove(_kPhoneNumber);
    currentUser.value = null;
  }

  static Future<String?> sendSmsCode(String phoneNumber) async {
    try {
      final uri = Uri.parse('$kApiBaseUrl/cp/sendSmsCode');
      final resp = await http.post(uri, body: {'phoneNumber': phoneNumber});
      if (resp.statusCode != 200) {
        return '发送失败，状态码：${resp.statusCode}';
      }
      final data = jsonDecode(resp.body);
      if (data is Map && (data['code'] == 200 || data['code'] == '200')) {
        return null;
      }
      return data is Map ? (data['msg']?.toString() ?? '发送失败') : '发送失败';
    } catch (e) {
      return '发送异常：$e';
    }
  }

  /// 注销账号，成功返回 null，失败返回错误信息。
  static Future<String?> deleteAccount({
    required int userId,
    required String phoneNumber,
    required String smsCode,
  }) async {
    try {
      final uri = Uri.parse('$kApiBaseUrl/cp/deleteAccount');
      final resp = await http.post(uri, body: {
        'userId': userId.toString(),
        'phoneNumber': phoneNumber,
        'smsCode': smsCode,
      });
      if (resp.statusCode != 200) {
        return '注销失败，状态码：${resp.statusCode}';
      }
      final data = jsonDecode(resp.body);
      if (data is Map && (data['code'] == 200 || data['code'] == '200')) {
        await logout();
        return null;
      }
      return data is Map ? (data['msg']?.toString() ?? '注销失败') : '注销失败';
    } catch (e) {
      return '注销异常：$e';
    }
  }
}
