import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Forgot password: phone + SMS + new password (same sendSmsCode as register).
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

/// UI copy as \\u escapes so the file stays valid UTF-8 on all editors/platforms.
abstract final class _S {
  static const forgotTitle = '\u5fd8\u8bb0\u5bc6\u7801';
  static const enterPhone = '\u8bf7\u8f93\u5165\u624b\u673a\u53f7';
  static const codeSent = '\u9a8c\u8bc1\u7801\u5df2\u53d1\u9001';
  static const sendFail = '\u53d1\u9001\u9a8c\u8bc1\u7801\u5931\u8d25\uff1a';
  static const unknownErr = '\u672a\u77e5\u9519\u8bef';
  static const sendFailHttp = '\u53d1\u9001\u9a8c\u8bc1\u7801\u5931\u8d25\uff0c\u72b6\u6001\u7801\uff1a';
  static const sendEx = '\u53d1\u9001\u9a8c\u8bc1\u7801\u5f02\u5e38\uff1a';
  static const fillAll = '\u8bf7\u5b8c\u6574\u586b\u5199\u624b\u673a\u53f7\u3001\u9a8c\u8bc1\u7801\u548c\u65b0\u5bc6\u7801';
  static const pwdLen = '\u65b0\u5bc6\u7801\u957f\u5ea6\u5e94\u4e3a 6\uff5e16 \u4e2a\u5b57\u7b26';
  static const pwdMismatch = '\u4e24\u6b21\u8f93\u5165\u7684\u5bc6\u7801\u4e0d\u4e00\u81f4';
  static const resetOk = '\u5bc6\u7801\u5df2\u91cd\u7f6e\uff0c\u8bf7\u4f7f\u7528\u65b0\u5bc6\u7801\u767b\u5f55';
  static const resetFail = '\u91cd\u7f6e\u5931\u8d25\uff1a';
  static const resetFailHttp = '\u91cd\u7f6e\u5931\u8d25\uff0c\u72b6\u6001\u7801\uff1a';
  static const resetEx = '\u91cd\u7f6e\u5f02\u5e38\uff1a';
  static const labelCode = '\u9a8c\u8bc1\u7801';
  static const hintCode = '\u8bf7\u8f93\u5165\u9a8c\u8bc1\u7801';
  static const getCode = '\u83b7\u53d6\u9a8c\u8bc1\u7801';
  static const labelNewPwd = '\u65b0\u5bc6\u7801';
  static const hintPwdLen = '6~16\u4e2a\u5b57\u7b26';
  static const labelConfirm = '\u786e\u8ba4\u65b0\u5bc6\u7801';
  static const hintConfirm = '\u518d\u6b21\u8f93\u5165\u65b0\u5bc6\u7801';
  static const btnReset = '\u91cd\u7f6e\u5bc6\u7801';
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _passwordConfirmController =
      TextEditingController();

  bool _sendingCode = false;
  bool _submitting = false;

  static const String _baseUrl = kApiBaseUrl;

  @override
  void dispose() {
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    super.dispose();
  }

  Future<void> _onSendCodePressed() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_S.enterPhone)),
      );
      return;
    }

    setState(() => _sendingCode = true);
    try {
      final uri = Uri.parse('$_baseUrl/cp/sendSmsCode');
      final resp = await http.post(uri, body: {'phoneNumber': phone});

      debugPrint('sendSmsCode(reset) status=${resp.statusCode} body=${resp.body}');

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && (data['code'] == 200 || data['code'] == '200')) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(_S.codeSent)),
          );
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    '${_S.sendFail}${data['msg'] ?? _S.unknownErr}')),
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${_S.sendFailHttp}${resp.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_S.sendEx}$e')),
      );
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  Future<void> _onResetPressed() async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    final pwd = _passwordController.text.trim();
    final pwd2 = _passwordConfirmController.text.trim();

    if (phone.isEmpty || code.isEmpty || pwd.isEmpty || pwd2.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_S.fillAll)),
      );
      return;
    }
    if (pwd.length < 6 || pwd.length > 16) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_S.pwdLen)),
      );
      return;
    }
    if (pwd != pwd2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_S.pwdMismatch)),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final uri = Uri.parse('$_baseUrl/$kCpResetPasswordPath');
      final resp = await http.post(uri, body: {
        'phoneNumber': phone,
        'password': pwd,
        'smsCode': code,
      });

      debugPrint('resetPassword status=${resp.statusCode} body=${resp.body}');

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        if (data is Map && (data['code'] == 200 || data['code'] == '200')) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(_S.resetOk)),
          );
          Navigator.pop(context);
        } else {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    '${_S.resetFail}${data['msg'] ?? _S.unknownErr}')),
          );
        }
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${_S.resetFailHttp}${resp.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_S.resetEx}$e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(_S.forgotTitle),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 24),
              Row(
                children: [
                  const Text('+86', style: TextStyle(fontSize: 16)),
                  const Icon(Icons.keyboard_arrow_down, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        hintText: _S.enterPhone,
                        border: UnderlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: _S.labelCode,
                        hintText: _S.hintCode,
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
                              _S.getCode,
                              style: TextStyle(color: Color(0xffb68c7b)),
                            ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: _S.labelNewPwd,
                  hintText: _S.hintPwdLen,
                  border: UnderlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordConfirmController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: _S.labelConfirm,
                  hintText: _S.hintConfirm,
                  border: UnderlineInputBorder(),
                ),
              ),
              const SizedBox(height: 32),
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
                  onPressed: _submitting ? null : _onResetPressed,
                  child: _submitting
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
                          _S.btnReset,
                          style: TextStyle(fontSize: 18),
                        ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
