import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'api_config.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:http/http.dart' as http;
import 'house_analysis_result_page.dart';
import 'house_analysis_list_page.dart';
import 'utils/asset_rotation.dart';

/// 房屋分析页面
/// 圆盘使用 fangwufenxi.png，罗盘旋转与左向显示逻辑与首页一致
class HouseAnalysisPage extends StatefulWidget {
  const HouseAnalysisPage({super.key});

  @override
  State<HouseAnalysisPage> createState() => _HouseAnalysisPageState();
}

class _HouseAnalysisPageState extends State<HouseAnalysisPage>
    with SingleTickerProviderStateMixin {
  double _heading = 0.0;
  double _targetHeading = 0.0;
  double _liveMagneticHeading = 0.0;
  bool _isLocked = false;
  double _lockedHeading = 0.0;
  double _compassRotationOffset = 0.0;
  bool _showRotationPanel = false;
  late AnimationController _animationController;
  late ValueNotifier<double> _displayHeadingNotifier;
  StreamSubscription<CompassEvent>? _compassSubscription;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat();

    _animationController.addListener(() {
      if (mounted) {
        setState(() {
          _heading = _smoothValue(_heading, _targetHeading);
        });
        final base = _isLocked ? _lockedHeading : _heading;
        _displayHeadingNotifier.value = (base + _compassRotationOffset) % 360;
      }
    });

    _startCompass();
    _displayHeadingNotifier = ValueNotifier(_heading);
    _fetchHouseAnalysisData();
  }

  /// POST 表单编码，支持中文
  String _encodeFormBody(Map<String, String> params) {
    return params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  /// 请求房屋分析接口并打印结果
  Future<void> _fetchHouseAnalysisData() async {
    try {
      final url = Uri.parse('http://aidashi.net/home/Index/luopan_fangwufenxi');
      
      // 构建form-data参数
      final formData = {
        'period': '9',  // 默认九运，可以根据实际情况调整
        'mountain': '子',  // 默认值，可以根据实际情况调整
        'direction': '午',  // 默认值，可以根据实际情况调整
      };
      
      final body = _encodeFormBody(formData);
      
      print('========== 房屋分析接口请求 ==========');
      print('请求URL: $url');
      print('请求方式: POST');
      print('Content-Type: application/x-www-form-urlencoded');
      print('请求参数: $formData');
      print('请求Body: $body');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
        },
        body: body,
        encoding: utf8,
      );
      
      print('========== 房屋分析接口请求结果 ==========');
      print('状态码: ${response.statusCode}');
      print('响应头: ${response.headers}');
      print('响应体: ${response.body}');
      
      if (response.statusCode == 200) {
        try {
          final jsonData = jsonDecode(response.body);
          print('解析后的JSON数据:');
          print(jsonEncode(JsonEncoder.withIndent('  ').convert(jsonData)));
        } catch (e) {
          print('JSON解析错误: $e');
        }
      } else {
        print('请求失败，状态码: ${response.statusCode}');
      }
      print('==========================================');
    } catch (e) {
      print('========== 房屋分析接口请求错误 ==========');
      print('错误信息: $e');
      print('==========================================');
    }
  }

  double _smoothValue(double current, double target) {
    return current + (target - current) * 0.15;
  }

  void _startCompass() {
    if (FlutterCompass.events != null) {
      _compassSubscription = FlutterCompass.events!.listen((event) {
        if (event.heading == null) return;

        double heading = event.heading!;
        if (heading < 0) heading = heading + 360;
        heading = heading % 360;

        double diff = heading - _targetHeading;
        if (diff > 180) {
          diff -= 360;
        } else if (diff < -180) diff += 360;
        final smoothed = _targetHeading + diff;
        var normalized = smoothed;
        if (normalized < 0) {
          normalized += 360;
        } else if (normalized >= 360) normalized -= 360;

        _liveMagneticHeading = normalized;
        if (!_isLocked) {
          _targetHeading = normalized;
        }
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _compassSubscription?.cancel();
    _displayHeadingNotifier.dispose();
    super.dispose();
  }

  String _getDirection(double heading) {
    const directions = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
    int index = ((heading + 22.5) / 45).floor() % 8;
    return directions[index];
  }

  String _getSittingDirection(double heading) => mountainAt(heading);

  String _getOppositeSittingDirection(double heading) =>
      oppositeMountainAt(heading);

  String _getSittingDirectionText(double heading) =>
      formatMountainFacing(heading);

  /// 显示“使用说明”弹窗（样式与“制作立极尺”弹窗类似）
  void _showUsageDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                const Text(
                  '使用说明',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          '1. 站在屋内，确定坐向，例如：子山午向，点击下方“开始分析”按钮。',
                          style: TextStyle(fontSize: 14, height: 1.5),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '2. 选择入伙年份，例如：2026年入伙，选择“2024-2043(九运)”。',
                          style: TextStyle(fontSize: 14, height: 1.5),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '3. 按“确定”查看分析结果。',
                          style: TextStyle(fontSize: 14, height: 1.5),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '4. 输入“房屋名称”及“单元”，再点击“保存分析结果”。',
                          style: TextStyle(fontSize: 14, height: 1.5),
                        ),
                        SizedBox(height: 12),
                        Text(
                          '在房屋分析界面中点击“分析列表”就能查看已经保存的房屋分析结果。',
                          style: TextStyle(fontSize: 14, height: 1.5),
                        ),
                        SizedBox(height: 12),
                        Text(
                          '注意：\n1. 使用时应远离家中的大型电器、电线或磁石等会影响磁场的物品。\n2. 本八宅分析法为坐山起伏法。',
                          style: TextStyle(fontSize: 14, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                    },
                    child: const Text(
                      '确定',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAnalysisDialog() {
    String selectedYear = '2024-2043 (九运)';
    final yearOptions = [
      '1864-1883 (一运)',
      '1884-1903 (二运)',
      '1904-1923 (三运)',
      '1924-1943 (四运)',
      '1944-1963 (五运)',
      '1964-1983 (六运)',
      '1984-2003 (七运)',
      '2004-2023 (八运)',
      '2024-2043 (九运)',
    ];

    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ValueListenableBuilder<double>(
                      valueListenable: _displayHeadingNotifier,
                      builder: (context, heading, _) =>
                          _buildDialogRow(
                              '坐向:', _getSittingDirectionText(heading)),
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          builder: (ctx) => SafeArea(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight:
                                    MediaQuery.of(ctx).size.height * 0.5,
                              ),
                              child: ListView(
                                shrinkWrap: true,
                                children: yearOptions.map((opt) {
                                  return ListTile(
                                    title: Text(opt),
                                    onTap: () {
                                      setDialogState(() => selectedYear = opt);
                                      Navigator.pop(ctx);
                                    },
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        );
                      },
                      child: _buildDialogRow(
                        '年份:',
                        '$selectedYear  ▼',
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              '取消',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              final heading =
                                  _displayHeadingNotifier.value;
                              final sittingText =
                                  _getSittingDirectionText(heading);
                              final direction = _getDirection(heading);
                              final degree =
                                  heading.toStringAsFixed(0);
                              final mountain =
                                  _getOppositeSittingDirection(heading);
                              final facing =
                                  _getSittingDirection(heading);
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      HouseAnalysisResultPage(
                                    sittingDirectionText: sittingText,
                                    directionWithDegree:
                                        '$direction$degree°',
                                    selectedYear: selectedYear,
                                    mountain: mountain,
                                    direction: facing,
                                  ),
                                ),
                              );
                            },
                            child: const Text(
                              '确定',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildDialogRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseHeading = _isLocked ? _lockedHeading : _heading;
    final displayHeading = (baseHeading + _compassRotationOffset) % 360;
    final sittingDirectionText = _getSittingDirectionText(displayHeading);
    final direction = _getDirection(displayHeading);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildHouseDirection(
                      sittingDirectionText, direction, displayHeading),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _buildCompass(displayHeading),
                        Positioned(
                          right: 20,
                          bottom: 20,
                          child: _buildLockButton(),
                        ),
                        if (_showRotationPanel)
                          Positioned(
                            right: 16,
                            top: 80,
                            child: _buildRotationPanel(),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _buildStartButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '房屋分析',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeaderButton('分析列表'),
              const SizedBox(height: 8),
              _buildHeaderButton('使用说明'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton(String label) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        if (label == '使用说明') {
          _showUsageDialog();
        } else if (label == '分析列表') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const HouseAnalysisListPage()),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.rectangle,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.red, width: 1.5),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _buildHouseDirection(
      String sittingDirectionText, String direction, double displayHeading) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.home,
              size: 64,
              color: Colors.orange[700],
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Icon(
                Icons.check_circle,
                size: 24,
                color: Colors.orange[700],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '$sittingDirectionText $direction${displayHeading.toStringAsFixed(0)}°',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildLockButton() {
    return ElevatedButton.icon(
      onPressed: () {
        setState(() {
          if (_isLocked) {
            _isLocked = false;
            _showRotationPanel = false;
            _compassRotationOffset = 0.0;
          } else {
            _isLocked = true;
            _lockedHeading = _heading;
            _compassRotationOffset = 0.0;
            _showRotationPanel = true;
          }
          final base = _isLocked ? _lockedHeading : _heading;
          _displayHeadingNotifier.value = (base + _compassRotationOffset) % 360;
        });
      },
      icon: Icon(
        _isLocked ? Icons.lock : Icons.lock_open,
        size: 18,
        color: Colors.white,
      ),
      label: Text(
        _isLocked ? '已锁定' : '未锁定',
        style: const TextStyle(fontSize: 12, color: Colors.white),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.black54,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  Widget _buildRotationPanel() {
    return GestureDetector(
      onPanUpdate: (details) {
        if (!_isLocked) return;
        double sensitivity = 0.5;
        double delta = -details.delta.dy * sensitivity;
        double newOffset =
            (_compassRotationOffset + delta).clamp(-180.0, 180.0);
        if ((newOffset - _compassRotationOffset).abs() > 0.01) {
          setState(() => _compassRotationOffset = newOffset);
          _displayHeadingNotifier.value =
              (_lockedHeading + newOffset) % 360;
        }
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 56,
        constraints: const BoxConstraints(minHeight: 220),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withOpacity(0.5),
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: '上下滑动此处调整罗盘角度'
              .split('')
              .map((char) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(
                      char,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildCompass(double displayHeading) {
    final screenSize = MediaQuery.of(context).size;
    // 罗盘宽度铺满屏幕，两边抵拢
    final compassSize = screenSize.width;

    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.rotate(
          angle: (-displayHeading * pi / 180 + pi / 2),
          child: Container(
            width: compassSize,
            height: compassSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipOval(
              child: AppAssetImage(
                assetPath: 'assets/fangwu/fangwufenxi.png',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.amber[100],
                    child: const Center(
                      child: Icon(Icons.error, color: Colors.grey, size: 48),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        Stack(
          alignment: Alignment.center,
          children: [
            // 天心十道：贯穿整个罗盘直径（与首页 CompassDetailPage 一致）
            IgnorePointer(
              child: CustomPaint(
                size: Size(compassSize, compassSize),
                painter: _CrosshairPainter(),
              ),
            ),
            // 中心气泡
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black, width: 2),
              ),
            ),
            // 罗盘指针：不随盘面旋转，始终指向磁北（0°）
            IgnorePointer(
              child: Transform.rotate(
                angle: luopanNeedleRotationRadians(_liveMagneticHeading),
                child: AppAssetImage(
                  assetPath: 'assets/luopanzhizhen.png',
                  width: compassSize * 0.30,
                  height: compassSize * 0.30,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return CustomPaint(
                      size: Size(compassSize * 0.18, compassSize * 0.18),
                      painter: _CompassNeedlePainter(),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStartButton() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton(
          onPressed: () {
            _showAnalysisDialog();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text(
            '开始分析',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CompassNeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final path = Path();
    final center = Offset(size.width / 2, size.height / 2);

    paint.color = Colors.red;
    path.moveTo(center.dx, center.dy - size.height / 2);
    path.lineTo(center.dx - 8, center.dy);
    path.lineTo(center.dx, center.dy + 5);
    path.lineTo(center.dx + 8, center.dy);
    path.close();
    canvas.drawPath(path, paint);

    paint.color = Colors.white;
    path.reset();
    path.moveTo(center.dx, center.dy + size.height / 2);
    path.lineTo(center.dx - 8, center.dy);
    path.lineTo(center.dx, center.dy - 5);
    path.lineTo(center.dx + 8, center.dy);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
