import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'about_page.dart';
import 'webview_page.dart';
import 'forgot_password_page.dart';
/// 注册页面（手机号 + 验证码 + 新密码）
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _agreeProtocol = false;
  bool _sendingCode = false;
  bool _registering = false;

  /// 后端地址：统一从 api_config.dart 读取
  static const String _baseUrl = kApiBaseUrl;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('注册'),
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

                // 验证码 + 按钮
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codeController,
                        decoration: const InputDecoration(
                          labelText: '验证码',
                          hintText: '请输入验证码',
                          border: UnderlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      height: 40,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xffb68c7b)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _sendingCode ? null : _onSendCodePressed,
                        child: _sendingCode
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                      Color(0xffb68c7b)),
                                ),
                              )
                            : const Text(
                                '获取验证码',
                                style: TextStyle(color: Color(0xffb68c7b)),
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 新密码
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '新密码',
                    hintText: '6~16个字符',
                    border: UnderlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 32),

                // 注册按钮
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
                    onPressed: _registering ? null : _onRegisterPressed,
                    child: _registering
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
                            '注册',
                            style: TextStyle(fontSize: 18),
                          ),
                  ),
                ),

                const SizedBox(height: 16),

                // 用户登录 / 忘记密码
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text('用户登录'),
                    ),
                    TextButton(
                      onPressed: _onForgetPasswordPressed,
                      child: const Text('忘记密码'),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // 协议勾选（Wrap 防止溢出）
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

                // 其它登录方式 + 微信按钮（暂不开放）
                // const Text(
                //   '其它登录方式',
                //   style: TextStyle(fontSize: 16),
                // ),
                // const SizedBox(height: 12),
                // GestureDetector(
                //   onTap: _onWechatLoginPressed,
                //   child: const CircleAvatar(
                //     radius: 32,
                //     backgroundColor: Color(0xff1AAD19),
                //     child: Icon(
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

  /// 发送验证码
  Future<void> _onSendCodePressed() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入手机号')),
      );
      return;
    }

    setState(() => _sendingCode = true);
    try {
      final uri = Uri.parse('$_baseUrl/cp/sendSmsCode');
      final resp = await http.post(uri, body: {'phoneNumber': phone});

      if (!mounted) return;

      debugPrint('sendSmsCode status=${resp.statusCode} body=${resp.body}');

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && (data['code'] == 200 || data['code'] == '200')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('验证码已发送')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('发送验证码失败：${data['msg'] ?? '未知错误'}')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送验证码失败，状态码：${resp.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送验证码异常：$e')),
      );
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  /// 注册
  Future<void> _onRegisterPressed() async {
    if (!_agreeProtocol) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先阅读并同意《用户协议》和《隐私政策》')),
      );
      return;
    }
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    final pwd = _passwordController.text.trim();
    if (phone.isEmpty || code.isEmpty || pwd.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请完整填写手机号、验证码和密码')),
      );
      return;
    }

    setState(() => _registering = true);
    try {
      final uri = Uri.parse('$_baseUrl/cp/register');
      final resp = await http.post(uri, body: {
        'phoneNumber': phone,
        'password': pwd,
        'smsCode': code,
      });

      if (!mounted) return;

      debugPrint('register status=${resp.statusCode} body=${resp.body}');

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && (data['code'] == 200 || data['code'] == '200')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('注册成功，请登录')),
          );
          Navigator.pop(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('注册失败：${data['msg'] ?? '未知错误'}')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('注册失败，状态码：${resp.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('注册异常：$e')),
      );
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  void _onForgetPasswordPressed() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
    );
  }

  void _onWechatLoginPressed() {
    // TODO: 微信快速注册/登录逻辑
  }
}

