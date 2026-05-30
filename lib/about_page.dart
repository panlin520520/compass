import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_config.dart';
import 'external_url_launcher.dart';
import 'webview_page.dart';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  static const String userAgreementUrl =
      'http://aidashi.net/home/Index/dashi_user_agreement';
  static const String privacyPolicyUrl =
      'http://aidashi.net/home/Index/dashi_privacy_policy?appname=luopan&sysOS=android';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('关于我们'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          const SizedBox(height: 40),
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: AppAssetImage(
                assetPath: 'assets/logo.png',
                width: 120,
                height: 120,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildItem(
                    context,
                    title: '用户协议',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const WebViewPage(
                            title: '用户协议',
                            url: userAgreementUrl,
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  _buildItem(
                    context,
                    title: '隐私协议',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const WebViewPage(
                            title: '隐私政策',
                            url: privacyPolicyUrl,
                          ),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 16, endIndent: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: const [
                        Text(
                          '备案号',
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF3A7BFF),
                          ),
                        ),
                        Text(
                          '沪ICP备19030261号-11A',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context,
      {required String title, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF3A7BFF),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

/// 我的客服 · 添加客服微信
class CustomerServicePage extends StatelessWidget {
  const CustomerServicePage({super.key});

  static const Color _primaryRed = Color(0xFFB30000);
  static const Color _pageBg = Color(0xFFF5F7FA);
  static const String _wechatId = 'qihuowangluo888';
  static const String _email = 'qwezcl@aliyun.com';
  static const String _kefuAssetPath = 'assets/kefu.jpg';

  Future<void> _copyText(BuildContext context, String text, String tip) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tip), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _copyAndOpenWeChat(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: _wechatId));
    if (!context.mounted) return;

    var opened = false;
    for (final uri in [
      Uri.parse('weixin://'),
      Uri.parse('wechat://'),
    ]) {
      try {
        if (await ExternalUrlLauncher.canOpenUrl(uri)) {
          opened = await ExternalUrlLauncher.openUrl(uri);
          if (opened) break;
        }
      } catch (_) {}
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened ? '已复制微信号，正在打开微信…' : '已复制微信号，请手动打开微信添加客服',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _copyChip(BuildContext context, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: _primaryRed, width: 1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Text(
          '复制',
          style: TextStyle(color: _primaryRed, fontSize: 14),
        ),
      ),
    );
  }

  Widget _contactRow({
    required BuildContext context,
    required String label,
    required String value,
    required VoidCallback onCopy,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 16, color: Color(0xFF333333)),
                children: [
                  TextSpan(text: label),
                  TextSpan(
                    text: value,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
          _copyChip(context, onCopy),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: _pageBg,
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: _primaryRed,
            child: Column(
              children: [
                SizedBox(
                  height: topInset + kToolbarHeight,
                  child: AppBar(
                    title: const Text('添加客服微信'),
                    centerTitle: true,
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    foregroundColor: Colors.white,
                    surfaceTintColor: Colors.transparent,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 56),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: AppAssetImage(
                        assetPath: _kefuAssetPath,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(
                              Icons.qr_code_2,
                              size: 80,
                              color: Colors.grey,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  const Text(
                    '截图保存二维码，走好运',
                    style: TextStyle(
                      color: _primaryRed,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 28),
                  _contactRow(
                    context: context,
                    label: '微信号：',
                    value: _wechatId,
                    onCopy: () => _copyText(context, _wechatId, '微信号已复制'),
                  ),
                  _contactRow(
                    context: context,
                    label: '邮箱：',
                    value: _email,
                    onCopy: () => _copyText(context, _email, '邮箱已复制'),
                  ),
                  const SizedBox(height: 48),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => _copyAndOpenWeChat(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryRed,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: const Text(
                          '复制并打开微信',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

