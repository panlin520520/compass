/// 简易登录态（内存态）
///
/// 先满足“登录后保持状态”的基本需求；后续需要持久化时再接入 shared_preferences。
class AuthState {
  static String? token;

  static bool get isLoggedIn => token != null && token!.isNotEmpty;

  static void logout() {
    token = null;
  }
}

