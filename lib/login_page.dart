import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'register_page.dart';
import 'forgot_password_page.dart';
import 'api_config.dart';
import 'about_page.dart';
import 'webview_page.dart';

/// 登录页面（账号密码 + 微信登录入口）
///
/// 顶部显示应用 Logo，下面是手机号、密码输入框和登录按钮，
/// 底部预留“其它登录方式”中的微信登录按钮。
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _agreeProtocol = false;
  bool _loggingIn = false;

  /// 后端地址：统一从 api_config.dart 读取
  static const String _baseUrl = kApiBaseUrl;

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('登录'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                // Logo
                SizedBox(
                  width: 140,
                  height: 140,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: AppAssetImage(
                      assetPath: 'assets/logo.png',
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 48),

                // 手机号输入
                Row(
                  children: [
                    const Text(
                      '+86',
                      style: TextStyle(fontSize: 16),
                    ),
                    const Icon(Icons.keyboard_arrow_down, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          hintText: '请输入手机号',
                          border: UnderlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 密码输入
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密码',
                    hintText: '6~16个字符',
                    border: UnderlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 32),

                // 登录按钮
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xffb68c7b),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _loggingIn ? null : _onLoginPressed,
                    child: _loggingIn
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            '登录账号',
                            style: TextStyle(fontSize: 18),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                // 注册 / 忘记密码
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _onRegisterPressed,
                      child: const Text('用户注册'),
                    ),
                    TextButton(
                      onPressed: _onForgetPasswordPressed,
                      child: const Text('忘记密码'),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // 协议勾选（使用 Wrap 防止小屏幕横向溢出）
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    SizedBox(
                      height: 24,
                      child: Checkbox(
                        value: _agreeProtocol,
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (v) {
                          setState(() {
                            _agreeProtocol = v ?? false;
                          });
                        },
                      ),
                    ),
                    const Text('我已阅读并同意'),
                    TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const WebViewPage(
                              title: '用户协议',
                              url: AboutPage.userAgreementUrl,
                            ),
                          ),
                        );
                      },
                      child: const Text('《用户协议》'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const WebViewPage(
                              title: '隐私政策',
                              url: AboutPage.privacyPolicyUrl,
                            ),
                          ),
                        );
                      },
                      child: const Text('《隐私政策》'),
                    ),
                  ],
                ),

                const SizedBox(height: 40),

              // 微信登录暂不开放（原 UI 注释）
              // const Text(
              //   '其它登录方式',
              //   style: TextStyle(fontSize: 16),
              // ),
              // const SizedBox(height: 12),
              // GestureDetector(
              //   onTap: _onWechatLoginPressed,
              //   child: CircleAvatar(
              //     radius: 32,
              //     backgroundColor: const Color(0xff1AAD19),
              //     child: const Icon(
              //       Icons.wechat,
              //       size: 36,
              //       color: Colors.white,
              //     ),
              //   ),
              // ),
              // const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onLoginPressed() async {
    if (!_agreeProtocol) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先阅读并同意《用户协议》和《隐私政策》')),
      );
      return;
    }

    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    if (phone.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入手机号和密码')),
      );
      return;
    }

    setState(() => _loggingIn = true);
    try {
      final uri = Uri.parse('$_baseUrl/cp/login');
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          'username': phone,
          'password': password,
        }),
      );

      if (!mounted) return;

      debugPrint('cp/login status=${resp.statusCode} body=${resp.body}');

      if (resp.statusCode != 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('登录失败，状态码：${resp.statusCode}')),
        );
        return;
      }

      final data = jsonDecode(resp.body);
      if (data is Map && (data['code'] == 200 || data['code'] == '200')) {
        final token = data['token']?.toString();
        if (token == null || token.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('登录失败：token 为空')),
          );
          return;
        }
        final int userId = int.tryParse(data['cpUserId']?.toString() ?? '') ?? 0;
        final nickName = data['nickName']?.toString() ?? phone;
        final avatar = data['avatar']?.toString() ?? '';
        final phoneNumber = data['phoneNumber']?.toString() ?? phone;
        await AuthService.saveLogin(
          userId: userId,
          token: token,
          nickName: nickName,
          avatar: avatar,
          phoneNumber: phoneNumber,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('登录成功')),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('登录失败：${data['msg'] ?? '未知错误'}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登录异常：$e')),
      );
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  void _onRegisterPressed() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RegisterPage()),
    );
  }

  void _onForgetPasswordPressed() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
    );
  }

  void _onWechatLoginPressed() {
    // TODO: 集成微信登录 SDK，获取 openId 后调用后端绑定/登录
  }
}

