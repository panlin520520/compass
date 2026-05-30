import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

import 'tianditu.dart';
import 'tianditu_pick_map_page.dart';
import 'auth_service.dart';
import 'login_page.dart';
import 'api_config.dart';
import 'utils/asset_rotation.dart';

/// 立极尺页面
/// 中间展示九星翻卦罗盘图：assets/liji/JiuXingFanGua.png
class LijiRulerPage extends StatefulWidget {
  const LijiRulerPage({super.key});

  @override
  State<LijiRulerPage> createState() => _LijiRulerPageState();
}

class _LijiRulerPageState extends State<LijiRulerPage> {
  // 用于获取中间正方形区域（AspectRatio）的 RenderBox，做坐标转换
  final GlobalKey _areaKey = GlobalKey();
  final GlobalKey _captureKey = GlobalKey(); // 截图区域
  final ImagePicker _imagePicker = ImagePicker();

  /// “选择立极尺罗盘”抽屉是否已打开（用于避免重复新开一个）
  bool _isLijiTemplateSheetOpen = false;

  /// “选择立极尺罗盘”抽屉内部的 setState，用于在抽屉已打开时强制刷新 UI
  void Function(void Function())? _lijiTemplateSheetSetState;
  double _scale = 1.0; // 罗盘缩放
  double _baseScale = 1.0;
  double _rotation = 0.0; // 逻辑旋转角度（弧度），0 表示初始姿态
  double _baseRotation = 0.0; // 手势开始时的基础旋转
  double _startAngle = 0.0; // 手势开始时手指相对于中心的角度
  double _containerSize = 0.0; // 罗盘容器的边长（用于计算中心点）
  double _baseCompassSize = 0.0; // 罗盘基础边长（未乘 _scale）
  double _ringSize = 0.0; // 圆环图大小（用于检测触摸点是否在圆环区域内）
  double _compassSize = 0.0; // 罗盘图大小（用于检测触摸点是否在罗盘区域内）
  bool _isCornerScaling = false; // 是否正在拖动四角缩放按钮
  double _cornerScaleAtDragStart = 1.0;
  double _cornerScaleStartDistance = 1.0;
  bool _canScale = false; // 本次手势是否允许缩放（双指手势）
  bool _isAtScaleBoundary = false; // 是否达到缩放边界，用于限制缩放范围
  bool _isCapturing = false; // 截图时隐藏部分装饰元素

  Offset _offset = Offset.zero; // 当前平移偏移量（用于放大后拖动查看细节）

  /// 立极尺底部抽屉中使用的罗盘模板（文件名使用拼音，展示名称使用中文）
  final List<_LijiTemplate> _templates = const [
    _LijiTemplate(
      englishFile: 'BaGeBaGuaErShiSiShan',
      chineseFile: '八格八卦二十四山',
      displayName: '八格·八卦·廿四山',
    ),
    _LijiTemplate(
      englishFile: 'BaGeBaGua',
      chineseFile: '八格八卦',
      displayName: '八格·八卦',
    ),
    _LijiTemplate(
      englishFile: 'BaGeErShiSiShan',
      chineseFile: '八格二十四山',
      displayName: '八格·二十四山',
    ),
    _LijiTemplate(
      englishFile: 'BaGeBaGuaWuKeDu',
      chineseFile: '八格八卦无刻度',
      displayName: '八格·八卦·无刻度',
    ),
    _LijiTemplate(
      englishFile: 'ShiErGeShiErDiZhi',
      chineseFile: '十二格十二地支',
      displayName: '十二格·十二地支',
    ),
    _LijiTemplate(
      englishFile: 'ErShiSiGeErShiSiShan',
      chineseFile: '二十四格二十四山',
      displayName: '二十四格·二十四山',
    ),
    _LijiTemplate(
      englishFile: 'LongMenBaJu',
      chineseFile: '龙门八局',
      displayName: '龙门八局',
    ),
    _LijiTemplate(
      englishFile: 'JiuXingFanGua',
      chineseFile: '九星翻卦',
      displayName: '九星翻卦',
    ),
    _LijiTemplate(
      englishFile: 'JiuGongBaGua',
      chineseFile: '九宫八卦',
      displayName: '九宫八卦',
    ),
    _LijiTemplate(
      englishFile: 'SanHeShuiFa',
      chineseFile: '三合水法',
      displayName: '三合水法',
    ),
  ];

  /// 当前选中的罗盘模板（默认为“九星翻卦”）
  _LijiTemplate _currentTemplate = const _LijiTemplate(
    englishFile: 'JiuXingFanGua',
    chineseFile: '九星翻卦',
    displayName: '九星翻卦',
  );

  /// 选项面板相关状态
  bool _tianXinShiDaoEnabled = true; // 天心十道（目前仅占位）
  bool _darkModeEnabled = false; // 深色模式（目前仅占位）
  double _lijiAngleDeg = 0.0; // 立极尺角度（用于选项面板显示，与 _rotation 同步）
  double _lijiOpacity = 1.0; // 立极尺透明度（0~1）
  double _backgroundAngleDeg = 0.0; // 底图角度（度）
  TiandituMapSelection? _mapBackground; // 选择的地图底图（天地图）
  File? _imageBackgroundFile; // 本地相册/相机选择的图片底图
  bool _auxLine1 = false;
  bool _auxLine2 = false;
  bool _auxLine3 = false;
  bool _useNineLuckCompass = true; // 是否使用九运罗盘图片替换立极尺罗盘
  double _auxAngle1 = 0.0; // 辅助线1 当前角度（弧度）
  double _auxAngle2 = 2 * pi / 3; // 辅助线2 初始角度
  double _auxAngle3 = 4 * pi / 3; // 辅助线3 初始角度
  int? _draggingAuxIndex; // 正在拖动的辅助线索引：1/2/3
  /// 单指手势：0=未确定，1=圆环旋转，2=罗盘内平移
  int _singleFingerGesture = 0;
  bool _isLijiLocked = false; // 立极尺角度是否锁定

  /// 用户自定义立极尺模板
  final List<_LijiTemplate> _userTemplates = [];

  /// 为模板生成一个稳定的唯一 key，用于“选中态”判断
  ///
  /// 注意：自定义模板的 englishFile 目前为空字符串，不能用来做选中比较，否则会导致全部自定义模板都被判定为同一个。
  String _templateKey(_LijiTemplate t) {
    if (t.isUserTemplate) {
      return 'u:${t.assetPath}|${t.displayName}|${t.innerSegments}|${t.outerSegments}|'
          '${t.add24Mountains ? 1 : 0}${t.addBagua ? 1 : 0}${t.add360 ? 1 : 0}';
    }
    return 'b:${t.englishFile}';
  }

  /// 后端地址（与登录保持一致）
  static const String _baseUrl = kApiBaseUrl;

  /// 九运选择列表（展示年份区间）
  static const List<String> _nineLuckPeriods = [
    '1864-1883（一运）',
    '1884-1903（二运）',
    '1904-1923（三运）',
    '1924-1943（四运）',
    '1944-1963（五运）',
    '1964-1983（六运）',
    '1984-2003（七运）',
    '2004-2023（八运）',
    '2024-2043（九运）',
  ];

  /// 九运玄空风水提示（与 [_nineLuckPeriods] 下标一一对应）
  static const List<_LuckHint> _nineLuckHints = [
    _LuckHint(
      title: '一运玄空风水提示：',
      detail: '双星会向、反吟伏吟、离宫打劫、九运令星入囚、正城门巽、副城门坤',
    ),
    _LuckHint(
      title: '二运玄空风水提示：',
      detail: '双星会坐、六运令星入囚、正城门巽',
    ),
    _LuckHint(
      title: '三运玄空风水提示：',
      detail: '双星会向、夫妇合十、离宫打劫、二运令星入囚、副城门坤',
    ),
    _LuckHint(
      title: '四运玄空风水提示：',
      detail: '双星会坐、八运令星入囚、正城门巽、副城门坤',
    ),
    _LuckHint(
      title: '五运玄空风水提示：',
      detail: '到山到向、夫妇合十、令星不入囚',
    ),
    _LuckHint(
      title: '六运玄空风水提示：',
      detail: '到山到向、夫妇合十、令星不入囚',
    ),
    _LuckHint(
      title: '七运玄空风水提示：',
      detail: '双星会坐、夫妇合十、二运令星入囚',
    ),
    _LuckHint(
      title: '八运玄空风水提示：',
      detail: '双星会向、离宫打劫、七运令星入囚、正城门巽',
    ),
    _LuckHint(
      title: '九运玄空风水提示：',
      detail: '双星会坐、反吟伏吟、四运令星入囚',
    ),
  ];

  /// 九运对应的罗盘图片资源（与 [_nineLuckPeriods] 下标一一对应）
  /// 资源位于 assets/liji/jiuyun 目录下
  static const List<String> _nineLuckCompassAssets = [
    'assets/liji/jiuyun/1yun.png', // 一运
    'assets/liji/jiuyun/2yun.png', // 二运
    'assets/liji/jiuyun/3yun.png', // 三运
    'assets/liji/jiuyun/4yun.png', // 四运
    'assets/liji/jiuyun/5yun.png', // 五运
    'assets/liji/jiuyun/6yun.png', // 六运
    'assets/liji/jiuyun/7qun.png', // 七运（文件名为 7qun.png）
    'assets/liji/jiuyun/8yun.png', // 八运
    'assets/liji/jiuyun/9yun.png', // 九运
  ];

  /// 当前选中的九运下标（0~8），默认选中“九运”
  int? _currentLuckIndex = 8;

  @override
  void initState() {
    super.initState();
    _loadUserTemplates();
  }

  /// 从后端加载当前用户自定义立极尺模板
  Future<void> _loadUserTemplates() async {
    if (!AuthService.isLoggedIn) return;

    // 安全获取当前登录用户及 userId，避免 null 导致的类型错误
    final authUser = AuthService.currentUser.value;
    final int userId = authUser?.userId ?? 0;
    if (userId == 0) {
      // 用户信息异常时直接返回，不请求后端
      debugPrint('加载立极尺模板：userId 无效，跳过请求');
      return;
    }

    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/cp/lijiTemplate/list?userId=$userId'),
      );
      if (resp.statusCode != 200) return;
      final data = json.decode(resp.body);
      if (data is! Map || (data['code'] != 200 && data['code'] != '200')) return;
      final list = (data['data'] as List?) ?? [];
      _userTemplates.clear();
      for (final item in list) {
        final Map<String, dynamic> m =
            Map<String, dynamic>.from(item as Map<dynamic, dynamic>);
        final String baseAsset = (m['baseAsset'] ?? '').toString();
        final String displayName = (m['name'] ?? '立极尺').toString();

        // 解析圈内/圈外格数及附加层配置
        int _parseInt(dynamic v) {
          if (v == null) return 0;
          if (v is int) return v;
          return int.tryParse(v.toString()) ?? 0;
        }

        bool _parseBool(dynamic v) {
          if (v == null) return false;
          if (v is bool) return v;
          final s = v.toString().toLowerCase();
          return s == 'true' || s == '1';
        }

        final int innerSegments = _parseInt(m['innerSegments']);
        final int outerSegments = _parseInt(m['outerSegments']);
        final bool add24Mountains = _parseBool(m['add24Mountains']);
        final bool addBagua = _parseBool(m['addBagua']);
        final bool add360 = _parseBool(m['add360']);

        _userTemplates.add(
          _LijiTemplate(
            englishFile: '',
            chineseFile: '',
            displayName: displayName,
            assetPath: baseAsset,
            innerSegments: innerSegments,
            outerSegments: outerSegments,
            add24Mountains: add24Mountains,
            addBagua: addBagua,
            add360: add360,
            isUserTemplate: true,
          ),
        );
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  /// 构建当前九运提示卡片
  Widget _buildLuckHintCard() {
    if (_currentLuckIndex == null) return const SizedBox.shrink();
    final hint = _nineLuckHints[_currentLuckIndex!];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            hint.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0053A6), // 接近截图中的蓝色
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hint.detail,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  /// 将全局坐标转换为中间正方形区域（罗盘/圆环区域）内的局部坐标
  Offset _toAreaLocal(Offset globalPoint) {
    final box = _areaKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return Offset.zero;
    return box.globalToLocal(globalPoint);
  }

  /// 保存当前底图 + 罗盘图（不含圆环 yuanhuan.png），并叠加注释到相册
  Future<void> _saveMeasurementToAlbum({required String annotation}) async {
    // 请求必要权限（不同 Android 版本会忽略不支持的权限）
    try {
      await Permission.photos.request();
      await Permission.storage.request();
    } catch (_) {}

    final prevCapturing = _isCapturing;
    if (mounted) {
      setState(() => _isCapturing = true);
    }
    await WidgetsBinding.instance.endOfFrame;

    try {
      final boundary =
          _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('截图区域未准备好');
      }

      final pixelRatio = View.of(context).devicePixelRatio;
      final uiImage = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData =
          await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('截图失败');
      }
      final pngBytes = byteData.buffer.asUint8List();

      // 在截图上绘制注释文字（左上角白色圆角框）
      final annotated = await _drawAnnotationOnPng(
        pngBytes: pngBytes,
        annotation: annotation,
      );

      // 通过平台通道交给 Android 原生保存到系统相册
      final name = 'liji_${DateTime.now().millisecondsSinceEpoch}.png';
      const channel = MethodChannel('liji_image_saver');
      final ok = await channel.invokeMethod<bool>(
            'saveImageToGallery',
            {
              'imageBytes': annotated,
              'name': name,
            },
          ) ??
          false;
      if (!ok) throw Exception('原生保存失败');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存到相册')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCapturing = prevCapturing);
      }
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// 发送测量结果图片到系统分享面板（微信好友 / 朋友圈 / QQ / 收藏等）
  Future<void> _shareMeasurement({required String annotation}) async {
    final prevCapturing = _isCapturing;
    if (mounted) {
      setState(() => _isCapturing = true);
    }
    try {
      await WidgetsBinding.instance.endOfFrame;

      final boundary =
          _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('截图区域未准备好');
      }

      final pixelRatio = View.of(context).devicePixelRatio;
      final uiImage = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('截图失败');
      }
      final pngBytes = byteData.buffer.asUint8List();

      final annotated = await _drawAnnotationOnPng(
        pngBytes: pngBytes,
        annotation: annotation,
      );

      final name = 'liji_${DateTime.now().millisecondsSinceEpoch}.png';
      const channel = MethodChannel('liji_image_saver');
      final ok = await channel.invokeMethod<bool>(
            'shareImage',
            {
              'imageBytes': annotated,
              'name': name,
            },
          ) ??
          false;
      if (!ok) throw Exception('原生分享失败');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('发送失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isCapturing = prevCapturing);
      }
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  /// 在 PNG 图片上绘制注释文本（左上角白色圆角框），返回新的 PNG 字节
  Future<Uint8List> _drawAnnotationOnPng({
    required Uint8List pngBytes,
    required String annotation,
  }) async {
    if (annotation.trim().isEmpty) return pngBytes;

    final codec = await ui.instantiateImageCodec(pngBytes);
    final frame = await codec.getNextFrame();
    final src = frame.image;
    final w = src.width.toDouble();
    final h = src.height.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
    canvas.drawImage(src, Offset.zero, Paint());

    const padding = 24.0;
    final maxWidth = w - padding * 2;
    final textSpan = TextSpan(
      text: annotation,
      style: const TextStyle(
        color: Colors.black,
        fontSize: 28,
        height: 1.25,
        fontWeight: FontWeight.w600,
      ),
    );
    final painter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth - 24);

    final boxRect = Rect.fromLTWH(
      padding,
      padding,
      painter.width + 24,
      painter.height + 18,
    );
    final rrect = RRect.fromRectAndRadius(boxRect, const Radius.circular(14));
    canvas.drawRRect(
      rrect,
      Paint()..color = Colors.white.withOpacity(0.82),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = Colors.black.withOpacity(0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    painter.paint(canvas, Offset(padding + 12, padding + 8));

    final picture = recorder.endRecording();
    final outImage = await picture.toImage(src.width, src.height);
    final outData =
        await outImage.toByteData(format: ui.ImageByteFormat.png);
    if (outData == null) return pngBytes;
    return outData.buffer.asUint8List();
  }

  /// 计算当前手指相对于罗盘中心的角度（弧度）
  double _computeAngle(Offset localPoint) {
    if (_containerSize <= 0) return 0.0;
    // 中心点需要加上当前的平移偏移量
    final center =
        Offset(_containerSize / 2 + _offset.dx, _containerSize / 2 + _offset.dy);
    final vector = localPoint - center;
    return atan2(vector.dy, vector.dx);
  }

  /// 命中测试：判断手指是否点中了某条辅助线，返回 1/2/3 或 null
  int? _hitTestAuxLine(Offset localPoint) {
    if (!_auxLine1 && !_auxLine2 && !_auxLine3) return null;
    if (_compassSize <= 0) return null;

    final center =
        Offset(_containerSize / 2 + _offset.dx, _containerSize / 2 + _offset.dy);
    final vector = localPoint - center;
    final distance = vector.distance;
    final radius = _compassSize / 2;

    // 只在靠近罗盘半径附近认为是点中了辅助线
    if (distance < radius * 0.4 || distance > radius * 1.2) return null;

    final angle = atan2(vector.dy, vector.dx);

    int? result;
    double bestDiff = double.infinity;

    void check(int index, bool enabled, double lineAngle) {
      if (!enabled) return;
      final diff = (angle - lineAngle + pi) % (2 * pi) - pi;
      final absDiff = diff.abs();
      // 允许大约 ±12° 的误差
      if (absDiff < 12 * pi / 180 && absDiff < bestDiff) {
        bestDiff = absDiff;
        result = index;
      }
    }

    check(1, _auxLine1, _auxAngle1);
    check(2, _auxLine2, _auxAngle2);
    check(3, _auxLine3, _auxAngle3);

    return result;
  }

  /// 检查触摸点是否在圆环图区域内
  bool _isPointInRingArea(Offset localPoint) {
    if (_containerSize <= 0 || _ringSize <= 0) return false;
    final center = _compassCenterLocal();
    final distance = (localPoint - center).distance;
    final outerRadius = _ringSize / 2;
    // 圆环带：只取外圈的一段宽度（避免在罗盘内部拖动也触发旋转）
    // 为了提高命中率，适当放宽内半径与容差
    final innerRadius = outerRadius * 0.7;
    const tolerance = 20.0; // 像素容差（手指不必点得太准）
    return distance >= innerRadius - tolerance &&
        distance <= outerRadius + tolerance;
  }

  /// 检查触摸点是否在罗盘图区域内
  bool _isPointInCompassArea(Offset localPoint) {
    if (_containerSize <= 0 || _compassSize <= 0) return false;
    final center = _compassCenterLocal();
    final distance = (localPoint - center).distance;
    final compassRadius = _compassSize / 2;
    const tolerance = 10.0; // 像素容差
    return distance <= compassRadius + tolerance;
  }

  Offset _compassCenterLocal() {
    return Offset(
      _containerSize / 2 + _offset.dx,
      _containerSize / 2 + _offset.dy,
    );
  }

  /// 是否点在四角缩放按钮上
  bool _isPointOnCornerHandle(Offset localPoint) {
    if (_baseCompassSize <= 0) return false;
    const handleHitRadius = 36.0;
    final center = _compassCenterLocal();
    final r = _baseCompassSize * _scale / 2;
    final corners = <Offset>[
      center + Offset(-r, -r),
      center + Offset(r, -r),
      center + Offset(-r, r),
      center + Offset(r, r),
    ];
    for (final corner in corners) {
      if ((localPoint - corner).distance <= handleHitRadius) return true;
    }
    return false;
  }

  void _onCornerScalePanStart(DragStartDetails details) {
    final local = _toAreaLocal(details.globalPosition);
    final center = _compassCenterLocal();
    var startDistance = (local - center).distance;
    if (startDistance < 8) startDistance = 8;
    setState(() {
      _isCornerScaling = true;
      _cornerScaleAtDragStart = _scale;
      _cornerScaleStartDistance = startDistance;
      _singleFingerGesture = 0;
      _draggingAuxIndex = null;
    });
  }

  void _onCornerScalePanUpdate(DragUpdateDetails details) {
    if (!_isCornerScaling) return;
    final local = _toAreaLocal(details.globalPosition);
    final center = _compassCenterLocal();
    var currentDistance = (local - center).distance;
    if (currentDistance < 8) currentDistance = 8;
    setState(() {
      _scale = (_cornerScaleAtDragStart *
              currentDistance /
              _cornerScaleStartDistance)
          .clamp(0.6, 6.0);
    });
  }

  void _onCornerScalePanEnd() {
    if (!_isCornerScaling) return;
    setState(() => _isCornerScaling = false);
  }

  /// 当前旋转对应的角度（0-360°），顺时针为正方向
  double get _rotationDegrees {
    double deg = -_rotation * 180 / pi;
    deg %= 360;
    if (deg < 0) deg += 360;
    return deg;
  }

  /// 用于标题和“立极尺角度”展示的角度（在 rotation 基础上整体 +180°）
  double get _headingDegreesForDisplay => (_rotationDegrees + 180) % 360;

  /// 根据模板信息构建罗盘图片
  /// 1) 如果是自定义模板（assetPath 不为空），使用“基础罗盘图 + 圈内/圈外格子图”叠加显示：
  ///    - 若基础图在 assets/liji/xuanzhe 下，则先根据附加层选项生成组合 PNG（如 二十四山-八卦-360度.png）作为底图
  /// 2) 否则优先使用拼音文件名，失败时回退到中文文件名
  Widget _buildTemplateImage(_LijiTemplate template) {
    if (template.assetPath != null && template.assetPath!.isNotEmpty) {
      // 先确定基础罗盘底图路径：
      // - 若在 assets/liji/xuanzhe 下，则按附加层组合生成最终 PNG 文件名
      // - 否则直接使用 assetPath 本身
      String basePath = template.assetPath!;
      if (basePath.contains('/xuanzhe/')) {
        basePath = _buildCompassImagePath(
          basePath,
          template.add24Mountains,
          template.addBagua,
          template.add360,
        );
      }

      // 使用“基础图 + 圈内/圈外格子图”叠加的方式组合
      final innerPath = _buildInnerRingImagePath(
        template.innerSegments,
        template.add24Mountains,
        template.addBagua,
        template.add360,
      );
      final outerPath = _buildOuterRingImagePath(template.outerSegments);

      return Stack(
        fit: StackFit.expand,
        children: [
          // 基础罗盘图
          AppAssetImage(
            assetPath: basePath,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: Colors.grey[200],
                child: const Icon(
                  Icons.image_not_supported,
                  color: Colors.grey,
                  size: 40,
                ),
              );
            },
          ),
          // 圈内图片（叠加在罗盘图上）
          if (innerPath != null)
            AppAssetImage(
              assetPath: innerPath,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('自定义模板圈内图片加载失败: $innerPath');
                return const SizedBox.shrink();
              },
            ),
          // 圈外图片（叠加在罗盘图上）
          if (outerPath != null)
            AppAssetImage(
              assetPath: outerPath,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('自定义模板圈外图片加载失败: $outerPath');
                return const SizedBox.shrink();
              },
            ),
        ],
      );
    }
    final englishPath = 'assets/liji/${template.englishFile}.png';
    final chinesePath = 'assets/liji/${template.chineseFile}.png';
    return AppAssetImage(
      assetPath: englishPath,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stack) {
        return AppAssetImage(
          assetPath: chinesePath,
          fit: BoxFit.cover,
        );
      },
    );
  }

  bool get _isSanHeShuiFaTemplate =>
      !_useNineLuckCompass && _currentTemplate.englishFile == 'SanHeShuiFa';

  /// 构建当前页面实际使用的罗盘图：
  /// 优先使用九运罗盘（根据当前选中的运数），否则使用立极尺模板
  Widget _buildCompassImage() {
    if (_useNineLuckCompass &&
        _currentLuckIndex != null &&
        _currentLuckIndex! >= 0 &&
        _currentLuckIndex! < _nineLuckCompassAssets.length) {
      final assetPath = _nineLuckCompassAssets[_currentLuckIndex!];
      return AppAssetImage(
        assetPath: assetPath,
        fit: BoxFit.cover,
      );
    }
    // 特殊处理：三合水法
    if (_isSanHeShuiFaTemplate) {
      debugPrint('进入三合水法处理逻辑');
      // 底图固定为 assets/sanheshuifa/sanheshuifa.png
      // 上层动态图根据当前顺时针角度叠加：
      //   assets/sanheshuifa/动态层/{step}.png
      // 其中 step 为最接近当前角度的 30° 节点（以节点为中心 ±15° 显示）：
      // 例如 270.png 在 255°~285° 区间显示（边界按项目约定处理）
      final basePath = 'assets/sanheshuifa/sanheshuifa.png';
      final normalized = (_rotationDegrees % 360 + 360) % 360; // 0..360

      double _circularDiff(double a, double b) {
        final diff = (a - b).abs();
        return diff > 180 ? 360 - diff : diff;
      }

      final lower = (normalized / 30).floor() * 30;
      final upper = (lower + 30) % 360;
      final dLower = _circularDiff(normalized, lower.toDouble());
      final dUpper = _circularDiff(normalized, upper.toDouble());

      int step;
      if (dLower < dUpper) {
        step = lower;
      } else if (dUpper < dLower) {
        step = upper;
      } else {
        // 刚好卡在两个节点的中点（差 15°）时：
        // 按项目资源约定，让 %60==30 的节点优先（可匹配 255/285 → 270 的示例）
        step = (lower % 60 == 30) ? lower : upper;
      }
      final overlayPath = 'assets/sanheshuifa/dongtaiceng/$step.png';

      // 调试信息
      debugPrint('=== 三合水法调试信息 ===');
      debugPrint('当前角度: ${_rotationDegrees.toStringAsFixed(1)}°');
      debugPrint('归一化角度: ${normalized.toStringAsFixed(1)}°');
      debugPrint('计算步进: $step°');
      debugPrint('叠加图片路径: $overlayPath');
      debugPrint('_useNineLuckCompass: $_useNineLuckCompass');
      debugPrint('_currentTemplate.englishFile: ${_currentTemplate.englishFile}');
      debugPrint('========================');

      return Stack(
        fit: StackFit.expand,
        children: [
          // 底图
          AppAssetImage(
            assetPath: basePath,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('底图加载失败: $basePath, 错误: $error');
              return Container(
                color: Colors.grey[200],
                child: const Icon(
                  Icons.image_not_supported,
                  color: Colors.grey,
                  size: 40,
                ),
              );
            },
          ),
          // 角度对应的动态层，若该度数图片不存在则忽略
          // 叠加层：跟随底图同向旋转（由父级 _rotation 负责），
          // 这里只做“按 step 节点的固定偏转”，使其在 ±15° 区间内保持对准 step（不随实时角度漂移）
          Transform.rotate(
            // 注意：不要抵消父级 _rotation，否则会出现叠加层与底图旋转方向相反
            angle: step * pi / 180,
            child: AppAssetImage(
              assetPath: overlayPath,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('动态层图片加载失败: $overlayPath');
                debugPrint('错误信息: $error');
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      );
    }
    return _buildTemplateImage(_currentTemplate);
  }

  /// 根据角度获取大致方向（北、东北、东...）
  String _getDirection(double heading) {
    const directions = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
    int index = ((heading + 22.5) / 45).floor() % 8;
    return directions[index];
  }

  String _getSittingDirection(double heading) => mountainAt(heading);

  String _getOppositeSittingDirection(double heading) =>
      oppositeMountainAt(heading);

  /// 顶部单行文案：空间不足时缩小字号，不显示省略号
  Widget _buildTopAdaptiveText(
    String text, {
    required Color color,
    double fontSize = 18,
    FontWeight fontWeight = FontWeight.w500,
    TextAlign textAlign = TextAlign.center,
  }) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: textAlign == TextAlign.center
          ? Alignment.center
          : Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        textAlign: textAlign,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // 标题显示用的方向角度（整体偏移180°，使默认显示为180度）
    final headingDeg = _headingDegreesForDisplay;
    final sittingText = formatMountainFacing(headingDeg);

    final isDark = _darkModeEnabled;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              color: isDark ? Colors.white : Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: _buildTopAdaptiveText(
          '$sittingText ${headingDeg.toStringAsFixed(1)}°',
          color: isDark ? Colors.white : Colors.black87,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: TextButton(
              onPressed: () {
                _showOperationHelpSheet(context);
              },
              child: const Text(
                '操作说明',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.red,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          // 顶部留白（提示卡片改为悬浮在底图之上）
          const SizedBox(height: 8),
          // 中间罗盘区域（双指：缩放/拖动；单指在圆环上：旋转）
          Expanded(
            child: LayoutBuilder(
              builder: (context, expandedConstraints) {
                return RepaintBoundary(
                  key: _captureKey,
                  child: Stack(
                    children: [
                      // 1) 本地相册/相机图片底图：优先级最高，铺满整个 Expanded 区域
                      if (_imageBackgroundFile != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Transform.rotate(
                              angle: _backgroundAngleDeg * pi / 180,
                              alignment: Alignment.center,
                              child: Image.file(
                                _imageBackgroundFile!,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),

                      // 2) 天地图底图：在未选择本地相册时生效
                      if (_imageBackgroundFile == null &&
                          _mapBackground != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: ClipRect(
                              child: OverflowBox(
                                maxWidth: double.infinity,
                                maxHeight: double.infinity,
                                child: Transform.rotate(
                                  angle: _backgroundAngleDeg * pi / 180,
                                  alignment: Alignment.center,
                                  child: SizedBox(
                                    // 放大画布，避免旋转后四角被裁剪
                                    width: expandedConstraints.maxWidth * 3.0,
                                    height:
                                        expandedConstraints.maxHeight * 3.0,
                                    child: FlutterMap(
                                      options: MapOptions(
                                        initialCenter: _mapBackground!.center,
                                        initialZoom: _mapBackground!.zoom,
                                        minZoom: 3,
                                        maxZoom: 18,
                                        interactionOptions:
                                            const InteractionOptions(
                                          flags: InteractiveFlag.none,
                                        ),
                                      ),
                                      children: [
                                        TileLayer(
                                          urlTemplate: Tianditu.tileUrlTemplate(
                                            _mapBackground!.isSatellite
                                                ? 'img'
                                                : 'vec',
                                          ),
                                          subdomains: const [
                                            '0',
                                            '1',
                                            '2',
                                            '3',
                                            '4',
                                            '5',
                                            '6',
                                            '7'
                                          ],
                                          userAgentPackageName:
                                              'com.example.flutter_application_1',
                                          maxZoom: 18,
                                        ),
                                        TileLayer(
                                          urlTemplate: Tianditu.tileUrlTemplate(
                                            _mapBackground!.isSatellite
                                                ? 'cia'
                                                : 'cva',
                                          ),
                                          subdomains: const [
                                            '0',
                                            '1',
                                            '2',
                                            '3',
                                            '4',
                                            '5',
                                            '6',
                                            '7'
                                          ],
                                          userAgentPackageName:
                                              'com.example.flutter_application_1',
                                          maxZoom: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                      // 3) 罗盘手势层（覆盖在底图上方）
                      GestureDetector(
                      behavior: HitTestBehavior
                          .translucent, // 手势作用于整个 Expanded 区域
                      onScaleStart: (details) {
                        final localPoint = _toAreaLocal(details.focalPoint);
                        if (_isCornerScaling ||
                            _isPointOnCornerHandle(localPoint)) {
                          return;
                        }
                        _baseScale = _scale;
                        _baseRotation = _rotation;
                        _startAngle = _computeAngle(localPoint);
                        _singleFingerGesture = 0;

                        // 单指操作时，优先检测是否命中某条辅助线，用于单独旋转辅助线
                        _draggingAuxIndex =
                            details.pointerCount == 1 ? _hitTestAuxLine(localPoint) : null;

                        if (details.pointerCount == 1 &&
                            !_isLijiLocked &&
                            _draggingAuxIndex == null) {
                          final inRing = _isPointInRingArea(localPoint);
                          // 圆环带与罗盘圆盘重叠：圆环优先旋转，仅内盘区域平移
                          if (inRing) {
                            _singleFingerGesture = 1;
                          } else if (_isPointInCompassArea(localPoint)) {
                            _singleFingerGesture = 2;
                          }
                        }

                        // 双指：用于缩放/拖动；单指：用于旋转/拖动
                        _canScale = details.pointerCount >= 2;
                      },
                      onScaleUpdate: (details) {
                        if (_isCornerScaling) return;
                        setState(() {
                          final localPoint = _toAreaLocal(details.focalPoint);

                          // 正在拖动某条辅助线：让该辅助线跟随手指围绕圆心旋转
                          if (_draggingAuxIndex != null &&
                              details.pointerCount == 1) {
                            final angle = _computeAngle(localPoint);
                            switch (_draggingAuxIndex) {
                              case 1:
                                _auxAngle1 = angle;
                                break;
                              case 2:
                                _auxAngle2 = angle;
                                break;
                              case 3:
                                _auxAngle3 = angle;
                                break;
                            }
                            return;
                          }

                          // 1. 双指：缩放 + 拖动（像看大图一样）
                          if (_canScale && details.pointerCount >= 2) {
                            final rawScale = _baseScale * details.scale;
                            _scale = rawScale.clamp(0.6, 6.0);

                            if (_scale > 1.0) {
                              _offset += details.focalPointDelta;
                            }
                          }

                          // 2. 单指：圆环带旋转；罗盘内部平移（与是否放大无关）
                          if (details.pointerCount == 1 && !_isLijiLocked) {
                            if (_singleFingerGesture == 1) {
                              final currentAngle = _computeAngle(localPoint);
                              final delta = currentAngle - _startAngle;
                              _rotation = _baseRotation + delta;
                            } else if (_singleFingerGesture == 2) {
                              _offset += details.focalPointDelta;
                            }
                          }
                        });
                      },
                      child: Center(
                        child: AspectRatio(
                          key: _areaKey,
                          aspectRatio: 1,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              // 记录容器边长，用于计算中心点
                              _containerSize = min(
                                constraints.maxWidth,
                                constraints.maxHeight,
                              );
                              // 罗盘和圆环的基础大小（不随缩放变化），基于容器尺寸
                              final baseCompassSize = _containerSize * 0.97;
                              _baseCompassSize = baseCompassSize;
                              final baseRingSize = baseCompassSize;

                              // 实际用于命中检测和文字半径的“可视半径”随缩放变化
                              _compassSize = baseCompassSize * _scale;
                              _ringSize = baseRingSize * _scale;

                              // 文字半径：固定在圆环图的圆环中间位置（使用缩放后的半径）
                              final ringRadius = _ringSize / 2;
                              final textRadius =
                                  ringRadius * 0.95; // 文字绘制在圆环中间偏外一点的位置
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  // 红色虚线矩形边框：与圆环/罗盘同步缩放、平移、旋转（截图时隐藏）
                                  if (!_isCapturing)
                                    IgnorePointer(
                                      child: Transform.translate(
                                        offset: _offset,
                                        child: Transform.scale(
                                          scale: _scale,
                                          child: Transform.rotate(
                                            angle: _rotation,
                                            child: SizedBox(
                                              width: baseCompassSize,
                                              height: baseCompassSize,
                                              child: CustomPaint(
                                                painter: _DashedRectPainter(
                                                  color: Colors.red.withOpacity(0.6),
                                                  strokeWidth: 1.0,
                                                  radius: 24,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                  // 可平移 + 缩放 + 透明度的内容（圆环图 + 罗盘图 + 圆环文字）
                                  Transform.translate(
                                    offset: _offset,
                                    child: Opacity(
                                      opacity: _lijiOpacity.clamp(0.0, 1.0),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          // 圆环图（与罗盘叠加，同步缩放，通过 Transform.scale 实现放大）
                                          // 截图时用户要求不包含 assets/liji/yuanhuan.png
                                          if (!_isLijiLocked && !_isCapturing)
                                            Transform.scale(
                                              scale: _scale,
                                              child: Transform.rotate(
                                                angle: _backgroundAngleDeg *
                                                    pi /
                                                    180,
                                                child: AppAssetImage(
                                                  assetPath: 'assets/liji/yuanhuan.png',
                                                  width: baseRingSize,
                                                  height: baseRingSize,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            ),
                                          // 中间罗盘图（可缩放、旋转），根据当前九运或立极尺模板显示
                                          Transform.scale(
                                            scale: _scale,
                                            child: Transform.rotate(
                                              angle: _rotation,
                                              child: Stack(
                                                alignment: Alignment.center,
                                                children: [
                                                  _buildCompassImage(),
                                                  // 在罗盘图正中央显示运数文字（一、二、三...九），仅在使用九运罗盘时显示
                                                  if (_useNineLuckCompass &&
                                                      _currentLuckIndex != null &&
                                                      _currentLuckIndex! >= 0 &&
                                                      _currentLuckIndex! < 9)
                                                    Transform.rotate(
                                                      angle: -_rotation, // 抵消罗盘旋转，保持文字正向
                                                      child: Text(
                                                        ['一', '二', '三', '四', '五', '六', '七', '八', '九'][_currentLuckIndex!],
                                                        style: TextStyle(
                                                          fontSize: baseCompassSize * 0.15,
                                                          fontWeight: FontWeight.bold,
                                                          color: Colors.black87,
                                                          shadows: [
                                                            Shadow(
                                                              offset: Offset(1, 1),
                                                              blurRadius: 2,
                                                              color: Colors.white.withOpacity(0.8),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          // 在圆环图上绘制文字（沿圆环横向，固定在圆环上；截图时隐藏）
                                          if (!_isLijiLocked && !_isCapturing)
                                            Positioned.fill(
                                              child: IgnorePointer(
                                                child: CustomPaint(
                                                  painter: _CircularTextPainter(
                                                    text: '滑动圆环旋转',
                                                    radius: textRadius,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),

                                  // 中心十字红线（水平 + 垂直）
                                  // 与罗盘同步缩放/移动，保持横竖方向不随罗盘旋转
                                  if (_tianXinShiDaoEnabled && !_isCapturing)
                                    IgnorePointer(
                                      child: Transform.translate(
                                        offset: _offset,
                                        child: Transform.scale(
                                          scale: _scale,
                                          child: SizedBox(
                                            width: baseCompassSize,
                                            height: baseCompassSize,
                                        child: CustomPaint(
                                          painter: _CrosshairPainter(),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                  // 三条可单独旋转的辅助线（红/绿/蓝），长度为罗盘直径
                                  if ((_auxLine1 || _auxLine2 || _auxLine3) &&
                                      _compassSize > 0)
                                    Positioned.fill(
                                      child: IgnorePointer(
                                        // 触摸交互由外层 GestureDetector 处理，这里只负责绘制
                                        child: CustomPaint(
                                          painter: _AuxLinesPainter(
                                            compassDiameter: _compassSize,
                                            angle1: _auxAngle1,
                                            angle2: _auxAngle2,
                                            angle3: _auxAngle3,
                                            show1: _auxLine1,
                                            show2: _auxLine2,
                                            show3: _auxLine3,
                                          ),
                                        ),
                                      ),
                                    ),

                                  // 四角缩放按钮：拖动可放大/缩小立极尺
                                  if (!_isCapturing)
                                    Transform.translate(
                                      offset: _offset,
                                      child: Transform.scale(
                                        scale: _scale,
                                        child: SizedBox(
                                          width: baseCompassSize,
                                          height: baseCompassSize,
                                          child: Stack(
                                            children: [
                                              _buildCornerButton(
                                                  Alignment.topLeft),
                                              _buildCornerButton(
                                                  Alignment.topRight),
                                              _buildCornerButton(
                                                  Alignment.bottomLeft),
                                              _buildCornerButton(
                                                  Alignment.bottomRight),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      ),

                      // 4) 九运提示卡片：悬浮在底图和罗盘之上（暂时隐藏）
                      // if (_currentLuckIndex != null && !_isCapturing)
                      //   Positioned(
                      //     top: 8,
                      //     left: 16,
                      //     right: 16,
                      //     child: IgnorePointer(
                      //       child: _buildLuckHintCard(),
                      //     ),
                      //   ),
                    ],
                  ),
                );
              },
            ),
          ),
          // 底部功能按钮栏
          SafeArea(
            top: false,
            child: _buildBottomBar(context),
          ),
        ],
      ),
    );
  }

  /// 抽屉顶部向下箭头：点击关闭当前 bottom sheet
  Widget _buildSheetDownCloseButton(BuildContext sheetContext) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black54),
      onPressed: () => Navigator.of(sheetContext).pop(),
    );
  }

  /// 与「选项」抽屉一致：顶部拖拽条 + 居中关闭箭头，可选标题
  Widget _buildSheetTopBar(
    BuildContext sheetContext, {
    String? title,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: _buildSheetDownCloseButton(sheetContext)),
        if (title != null) ...[
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }

  void _showOperationHelpSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final maxHeight = MediaQuery.of(ctx).size.height * 0.8;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(
                children: [
                  const Text(
                    '操作说明',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      child: const _OperationHelpContent(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE09A73)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text(
                        '确定',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 四个角上的缩放按钮：按住拖动可放大/缩小立极尺
  Widget _buildCornerButton(Alignment alignment) {
    final rotateQuarterTurn = alignment == Alignment.topLeft ||
        alignment == Alignment.bottomRight;
    return Align(
      alignment: alignment,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: _onCornerScalePanStart,
          onPanUpdate: _onCornerScalePanUpdate,
          onPanEnd: (_) => _onCornerScalePanEnd(),
          onPanCancel: _onCornerScalePanEnd,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Transform.rotate(
              angle: rotateQuarterTurn ? pi / 2 : 0,
              child: const Icon(
                Icons.open_in_full,
                size: 20,
                color: Colors.black54,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final items = [
      {'icon': Icons.trip_origin, 'label': '立极尺', 'selected': true},
      {'icon': Icons.star_border, 'label': '九运', 'selected': false},
      {'icon': Icons.tune, 'label': '选项', 'selected': false},
      {'icon': Icons.layers_outlined, 'label': '底图', 'selected': false},
      {'icon': Icons.download, 'label': '保存', 'selected': false},
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: items.map((item) {
          final selected = item['selected'] as bool;
          final label = item['label'] as String;
          return Expanded(
            child: InkWell(
              onTap: () {
                if (label == '立极尺') {
                  _showLijiTemplateSheet(context);
                } else if (label == '九运') {
                  _showNineLuckSheet(context);
                } else if (label == '选项') {
                  _showOptionsSheet(context);
                } else if (label == '底图') {
                  _showBackgroundSheet(context);
                } else if (label == '保存') {
                  _showSaveSheet(context);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    item['icon'] as IconData,
                    size: 24,
                    color: selected ? Colors.red : Colors.black54,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: selected ? Colors.red : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 显示立极尺罗盘模板选择抽屉
  ///
  /// 每次打开时都会重新加载用户自定义的立极尺模板，确保数据最新
  Future<void> _showLijiTemplateSheet(BuildContext context) async {
    // 如果抽屉已打开，则只刷新数据与 UI，不重复新开一个抽屉
    if (_isLijiTemplateSheetOpen) {
      await _loadUserTemplates();
      if (!mounted) return;
      final ss = _lijiTemplateSheetSetState;
      if (ss != null) ss(() {});
      return;
    }

    try {
      // 标记抽屉“正在打开”，防止用户短时间内重复点击打开多个
      _isLijiTemplateSheetOpen = true;

      await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final sheetHeight = MediaQuery.of(context).size.height * 0.7;
        // 控制当前抽屉内部的加载提示，只在该闭包内有效
        bool loading = true;
        bool requested = false;
        return StatefulBuilder(
          builder: (sheetCtx, sheetSetState) {
            _lijiTemplateSheetSetState = sheetSetState;

            // 首次 build 时在抽屉内部异步加载用户模板，并在完成后关闭“加载中”提示
            if (!requested) {
              requested = true;
              _loadUserTemplates().then((_) {
                if (!mounted) return;
                sheetSetState(() {
                  loading = false;
                });
              }).catchError((_) {
                if (!mounted) return;
                sheetSetState(() {
                  loading = false;
                });
              });
            }

            return SafeArea(
              top: false,
              child: SizedBox(
                height: sheetHeight,
                child: Column(
                  children: [
                    _buildSheetTopBar(
                      sheetCtx,
                      title: '选择立极尺罗盘',
                    ),
                    // 加载提示（只在首次从后端加载用户模板时显示）
                    if (loading)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 8),
                            Text(
                              '正在加载自定义立极尺模板...',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    else
                      const SizedBox(height: 8),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 16,
                          crossAxisSpacing: 16,
                          childAspectRatio: 0.8,
                        ),
                        itemCount: _templates.length + _userTemplates.length,
                        itemBuilder: (context, index) {
                          final allTemplates = [..._templates, ..._userTemplates];
                          final template = allTemplates[index];
                          // 前 _templates.length 个为内置模板，后面的为用户自定义模板
                          final bool isUserTemplate = index >= _templates.length;
                          final isSelected =
                              _templateKey(template) == _templateKey(_currentTemplate);
                          return InkWell(
                            onTap: () {
                              // 切换当前立极尺罗盘图，并关闭抽屉
                              setState(() {
                                _currentTemplate = template;
                                _useNineLuckCompass = false; // 显式使用立极尺罗盘
                              });
                              Navigator.of(sheetCtx).pop();
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Expanded(
                                  child: Stack(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: AspectRatio(
                                          aspectRatio: 1,
                                          child: _buildTemplateImage(template),
                                        ),
                                      ),
                                      if (isSelected)
                                        Positioned(
                                          right: 4,
                                          top: 4,
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: Colors.red.withOpacity(0.9),
                                              shape: BoxShape.circle,
                                            ),
                                            padding: const EdgeInsets.all(3),
                                            child: const Icon(
                                              Icons.check,
                                              size: 14,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isUserTemplate
                                      ? '${template.displayName}（自）'
                                      : template.displayName,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black87,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    // 底部添加按钮
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SafeArea(
                        top: false,
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              _showAddLijiLayerSheet(sheetCtx);
                            },
                            icon: const Icon(Icons.add, size: 20),
                            label: const Text(
                              '添加立极尺',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black87,
                              side: const BorderSide(
                                color: Color(0xFFEE7C2F),
                                width: 1.2,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
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
      },
    );
    } finally {
      // 无论正常关闭还是异常中断，都清理状态，避免“认为抽屉还开着”
      _isLijiTemplateSheetOpen = false;
      _lijiTemplateSheetSetState = null;
    }
  }

  /// 通用的分类选项加载函数
  Future<List<Map<String, String>>> _loadCategoryOptions(String category) async {
    final prefix = 'assets/liji/xuanzhe/$category/';
    const defaultPngPattern = '/默认.png';

    // 获取资源清单（如果失败，使用空集合）
    Set<String> assetPaths = {};
    try {
      // 尝试从 AssetManifest 加载资源列表
      final manifestContent =
          await loadAppAssetString('AssetManifest.json') ?? '';
      final Map<String, dynamic> manifestMap = json.decode(manifestContent);
      assetPaths = manifestMap.keys.toSet();
      debugPrint('资源清单中共有 ${assetPaths.length} 个资源');

      // 调试：显示一些相关的资源路径
      final relatedPaths = assetPaths.where((path) => path.contains('liji/xuanzhe')).take(5).toList();
      if (relatedPaths.isNotEmpty) {
        debugPrint('相关资源路径示例: ${relatedPaths.join(", ")}');
      }
    } catch (e) {
      debugPrint('加载 AssetManifest.json 失败: $e');
      debugPrint('将继续使用硬编码的文件夹列表，不进行资源验证');
    }

    // 定义每个分类的文件夹列表
    final Map<String, List<String>> categoryFolders = {
      '地盘': [
        '二十四三安灶诀',
        '二十四天星（徽盘）',
        '二十四山人伦别',
        '二十四山挨星诀',
        '元运二十四天星（九运）',
        '八路四路黄泉、地支黄泉',
        '八路四路黄泉煞',
        '地母翻卦（坤卦翻起)',
        '地盘正兼向度数（9度内）1',
        '地盘正兼向度数（9度内）2',
        '地盘正针二十四山',
        '地盘正针二十四山（三元阴阳）',
        '地盘正针二十四山（三合阴阳）1',
        '地盘正针二十四山（三合阴阳）2',
        '地盘正针二十四山五行（三合阴阳）',
        '地盘正针二十四山五行含天人地（三合阴阳）',
        '地盘正针二十四山含天人地三元龙（三元阴阳）',
        '地盘正针百二十分金1',
        '地盘正针百二十分金2',
        '地盘正针百二十分金五行',
        '替星盘（挨星）',
        '白虎黄泉',
      ],
      '先天八卦': [
        '先天八卦名',
        '先天八卦象',
        '先天八卦象、卦八方位',
        '先天八卦象与龙上八煞',
        '先天八卦象与龙上八煞、后天八卦名、洛书数',
      ],
      '后天八卦': [
        '九星飞泊',
        '八宅大游年歌诀',
        '后天八卦名',
        '后天八卦名、五行',
        '后天八卦名、洛书、洛书数',
        '后天八卦象',
        '后天八卦象、后天八卦名、洛书数',
        '年紫白飞星（2015年2029年）',
        '年紫白飞星（2015年2029年）年份',
        '月紫白飞星（2015年2029年）',
        '洛书',
        '洛书数',
      ],
      '方位': [
        '二十四方位',
        '八方位',
        '四大局',
      ],
      '六十龙': [
        '盈缩六十龙',
        '盈缩六十龙五行',
        '盈缩六十龙五行与浑天星度五行',
        '盈缩六十龙五行与浑天星度五行2',
        '透地六十龙四吉珠宝山卦方',
        '透地平分六十龙',
        '透地平分六十龙2',
        '透地龙三七、七三、五、正位',
      ],
      '七十二龙': [
        '穿山七十二龙',
        '穿山七十二龙、纳音五行',
      ],
      '人盘': [
        '人盘中针二十四山',
        '人盘中针二十四山赖公拨砂五行',
        '人盘中针百二十分金',
        '人盘正兼向度数（9度内）1',
        '人盘正兼向度数（9度内）2',
      ],
    };

    final folders = categoryFolders[category] ?? [];
    debugPrint('分类 $category 有 ${folders.length} 个文件夹');

    if (folders.isEmpty) {
      debugPrint('警告: 分类 $category 没有定义文件夹列表');
      return [];
    }

    // 构建选项列表，使用 AssetManifest 检查资源是否存在
    final List<Map<String, String>> options = [];
    int foundCount = 0;
    int notFoundCount = 0;

    for (final folderName in folders) {
      final assetPath = '$prefix$folderName$defaultPngPattern';

      // 检查资源是否在清单中
      final exists = assetPaths.contains(assetPath);

      if (exists) {
        foundCount++;
        debugPrint('  ✓ 资源存在: $assetPath');
      } else {
        notFoundCount++;
        debugPrint('  ✗ 资源不存在: $assetPath');
        // 尝试查找类似的路径（用于调试）
        final similarPaths = assetPaths.where((path) =>
          path.contains(folderName) || path.contains(category)
        ).take(3).toList();
        if (similarPaths.isNotEmpty) {
          debugPrint('    类似路径: ${similarPaths.join(", ")}');
        }
      }

      // 无论是否存在，都添加到选项中（让 Image.asset 的 errorBuilder 处理）
      options.add({
        'title': folderName,
        'asset': assetPath,
      });
    }

    // 按文件夹名称排序
    options.sort((a, b) => a['title']!.compareTo(b['title']!));

    debugPrint('加载$category选项: 共 ${folders.length} 个文件夹，构建了 ${options.length} 个选项，找到 $foundCount 个资源，未找到 $notFoundCount 个资源');

    if (options.isEmpty) {
      debugPrint('警告: $category 选项列表为空！');
    } else {
      debugPrint('前3个选项: ${options.take(3).map((o) => o['title']).join(", ")}');
    }

    return options;
  }

  /// 显示“添加立极尺”抽屉：选择一个圈层制作立极尺
  void _showAddLijiLayerSheet(BuildContext parentContext) {
    showModalBottomSheet(
      context: parentContext,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final categories = [
          '先天八卦',
          '后天八卦',
          '方位',
          '地盘',
          '六十龙',
          '七十二龙',
          '人盘',
        ];

        // 需要动态加载的分类
        final dynamicCategories = ['先天八卦', '后天八卦', '方位', '地盘', '六十龙', '七十二龙', '人盘'];

        int selectedIndex = 0;
        // 为每个分类维护独立的选项和加载状态
        final Map<String, List<Map<String, String>>?> categoryOptions = {};
        final Map<String, bool> categoryLoading = {};

        return StatefulBuilder(
          builder: (ctx, modalSetState) {
            final category = categories[selectedIndex];

            // 如果是需要动态加载的分类且还没有加载，则动态加载
            if (dynamicCategories.contains(category) &&
                categoryOptions[category] == null &&
                !(categoryLoading[category] ?? false)) {
              debugPrint('开始加载$category选项...');
              categoryLoading[category] = true;
              _loadCategoryOptions(category).then((options) {
                debugPrint('$category选项加载完成，找到 ${options.length} 个选项');
                if (ctx.mounted) {
                  modalSetState(() {
                    categoryOptions[category] = options;
                    categoryLoading[category] = false;
                  });
                }
              }).catchError((e, stackTrace) {
                debugPrint('加载$category选项出错: $e');
                debugPrint('堆栈: $stackTrace');
                // 即使出错，也尝试返回一个基本的选项列表
                // 使用同步方式构建基本选项（不依赖 AssetManifest）
                try {
                  final prefix = 'assets/liji/xuanzhe/$category/';
                  const defaultPngPattern = '/默认.png';
                  final Map<String, List<String>> categoryFolders = {
                    '地盘': ['二十四三安灶诀', '二十四天星（徽盘）', '二十四山人伦别', '二十四山挨星诀', '元运二十四天星（九运）', '八路四路黄泉、地支黄泉', '八路四路黄泉煞', '地母翻卦（坤卦翻起)', '地盘正兼向度数（9度内）1', '地盘正兼向度数（9度内）2', '地盘正针二十四山', '地盘正针二十四山（三元阴阳）', '地盘正针二十四山（三合阴阳）1', '地盘正针二十四山（三合阴阳）2', '地盘正针二十四山五行（三合阴阳）', '地盘正针二十四山五行含天人地（三合阴阳）', '地盘正针二十四山含天人地三元龙（三元阴阳）', '地盘正针百二十分金1', '地盘正针百二十分金2', '地盘正针百二十分金五行', '替星盘（挨星）', '白虎黄泉'],
                    '先天八卦': ['先天八卦名', '先天八卦象', '先天八卦象、卦八方位', '先天八卦象与龙上八煞', '先天八卦象与龙上八煞、后天八卦名、洛书数'],
                    '后天八卦': ['九星飞泊', '八宅大游年歌诀', '后天八卦名', '后天八卦名、五行', '后天八卦名、洛书、洛书数', '后天八卦象', '后天八卦象、后天八卦名、洛书数', '年紫白飞星（2015年2029年）', '年紫白飞星（2015年2029年）年份', '月紫白飞星（2015年2029年）', '洛书', '洛书数'],
                    '方位': ['二十四方位', '八方位', '四大局'],
                    '六十龙': ['盈缩六十龙', '盈缩六十龙五行', '盈缩六十龙五行与浑天星度五行', '盈缩六十龙五行与浑天星度五行2', '透地六十龙四吉珠宝山卦方', '透地平分六十龙', '透地平分六十龙2', '透地龙三七、七三、五、正位'],
                    '七十二龙': ['穿山七十二龙', '穿山七十二龙、纳音五行'],
                    '人盘': ['人盘中针二十四山', '人盘中针二十四山赖公拨砂五行', '人盘中针百二十分金', '人盘正兼向度数（9度内）1', '人盘正兼向度数（9度内）2'],
                  };
                  final folders = categoryFolders[category] ?? [];
                  final fallbackOptions = folders.map((folderName) {
                    return {
                      'title': folderName,
                      'asset': '$prefix$folderName$defaultPngPattern',
                    };
                  }).toList();
                  debugPrint('使用备用选项列表: ${fallbackOptions.length} 个');
                  if (ctx.mounted) {
                    modalSetState(() {
                      categoryLoading[category] = false;
                      categoryOptions[category] = fallbackOptions;
                    });
                  }
                } catch (fallbackError) {
                  debugPrint('构建备用选项列表也失败: $fallbackError');
                  if (ctx.mounted) {
                    modalSetState(() {
                      categoryLoading[category] = false;
                      categoryOptions[category] = [];
                    });
                  }
                }
              });
            }

            final options = dynamicCategories.contains(category)
                ? (categoryOptions[category] ?? [])
                : const [];

            // 如果正在加载，显示加载指示器
            final showLoading = dynamicCategories.contains(category) &&
                (categoryLoading[category] ?? false) &&
                categoryOptions[category] == null;
            // 如果加载完成但没有数据，显示提示
            final showEmpty = dynamicCategories.contains(category) &&
                !(categoryLoading[category] ?? false) &&
                categoryOptions[category] != null &&
                categoryOptions[category]!.isEmpty;

            return SafeArea(
              top: false,
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.8,
                child: Column(
                  children: [
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const SizedBox(width: 40),
                          const Text(
                            '选择一个圈层制作立极尺',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 90,
                            color: const Color(0xFFF5F5F5),
                            child: ListView.builder(
                              itemCount: categories.length,
                              itemBuilder: (context, index) {
                                final selected = index == selectedIndex;
                                return InkWell(
                                  onTap: () {
                                    modalSetState(() {
                                      selectedIndex = index;
                                    });
                                  },
                                  child: Container(
                                    color: selected
                                        ? Colors.white
                                        : Colors.transparent,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14, horizontal: 12),
                                    child: Text(
                                      categories[index],
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: selected
                                            ? Colors.red
                                            : Colors.black87,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: showLoading
                                  ? const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  : showEmpty
                                      ? const Center(
                                          child: Text(
                                            '暂无数据\n请检查资源文件是否正确配置',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: Colors.grey,
                                              fontSize: 14,
                                            ),
                                          ),
                                        )
                                      : GridView.builder(
                                      gridDelegate:
                                          const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        mainAxisSpacing: 16,
                                        crossAxisSpacing: 16,
                                        childAspectRatio: 0.9,
                                      ),
                                      itemCount: options.length,
                                      itemBuilder: (context, index) {
                                        final opt = options[index];
                                        return InkWell(
                                          onTap: () {
                                            // 这里传入父级页面上下文 parentContext，避免后续弹窗/抽屉关闭时把当前页面一起关闭
                                            _showCreateLijiRulerDialog(
                                              parentContext,
                                              defaultName: opt['title'] ?? '立极尺',
                                              previewAsset: opt['asset'],
                                            );
                                          },
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Expanded(
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  child: AspectRatio(
                                                    aspectRatio: 1,
                                                    child: Container(
                                                      color: Colors.white,
                                                      child: opt['asset'] != null
                                                          ? AppAssetImage(
                                                              assetPath: opt['asset']!,
                                                              fit: BoxFit.cover,
                                                              errorBuilder: (context, error, stackTrace) {
                                                                debugPrint('图片加载失败: ${opt['asset']}');
                                                                debugPrint('错误类型: ${error.runtimeType}');
                                                                debugPrint('错误详情: $error');
                                                                debugPrint('堆栈: $stackTrace');
                                                                return Container(
                                                                  color: Colors.grey[200],
                                                                  child: Column(
                                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                                    children: [
                                                                      const Icon(
                                                                        Icons.image_not_supported,
                                                                        color: Colors.grey,
                                                                        size: 40,
                                                                      ),
                                                                      const SizedBox(height: 4),
                                                                      Text(
                                                                        '加载失败',
                                                                        style: TextStyle(
                                                                          fontSize: 10,
                                                                          color: Colors.grey[600],
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                );
                                                              },
                                                            )
                                                          : const SizedBox.shrink(),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                opt['title'] ?? '',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black87,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 根据选中的附加层选项构建图片路径
  String _buildCompassImagePath(String baseAssetPath, bool add24Mountains, bool addBagua, bool add360) {
    // 从基础路径中提取文件夹路径（去掉文件名）
    // 例如: assets/liji/xuanzhe/地盘/二十四三安灶诀/默认.png
    // 提取: assets/liji/xuanzhe/地盘/二十四三安灶诀/
    final lastSlashIndex = baseAssetPath.lastIndexOf('/');
    if (lastSlashIndex == -1) return baseAssetPath;

    final folderPath = baseAssetPath.substring(0, lastSlashIndex + 1);

    // 根据选中的选项构建文件名
    final List<String> parts = [];
    if (add24Mountains) parts.add('二十四山');
    if (addBagua) parts.add('八卦');
    if (add360) parts.add('360度');

    String fileName;
    if (parts.isEmpty) {
      fileName = '默认.png';
    } else {
      fileName = '${parts.join('-')}.png';
    }

    return '$folderPath$fileName';
  }

  /// 构建圈内图片路径（根据附加层组合）
  String? _buildInnerRingImagePath(int segments, bool add24Mountains, bool addBagua, bool add360) {
    if (segments == 0) return null;

    // 根据选中的选项构建文件夹名称
    final List<String> parts = [];
    if (add24Mountains) parts.add('二十四山');
    if (addBagua) parts.add('八卦');
    if (add360) parts.add('360度');

    String folderName;
    if (parts.isEmpty) {
      folderName = '默认';
    } else {
      folderName = parts.join('-');
    }

    return 'assets/liji/圈内/$folderName/圈内/$segments.png';
  }

  /// 构建圈外图片路径（不分附加层组合）
  String? _buildOuterRingImagePath(int segments) {
    if (segments == 0) return null;
    return 'assets/liji/圈外/$segments.png';
  }

  /// 制作立极尺的模态框：设置名称、圈内/圈外格数和附加层
  void _showCreateLijiRulerDialog(
    BuildContext context, {
    required String defaultName,
    String? previewAsset,
  }) {
    final controller = TextEditingController(text: defaultName);
    int innerSegments = 0; // 0=无格, 8, 12, 24
    int outerSegments = 0;
    bool add24Mountains = false;
    bool addBagua = false;
    bool add360 = false;

    // 当前显示的预览图路径（根据附加层选项动态更新）
    String? currentPreviewAsset = previewAsset;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: StatefulBuilder(
            builder: (dialogCtx, setDialogState) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 4),
                    const Text(
                      '制作立极尺',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '立极尺名称',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: controller,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  border: UnderlineInputBorder(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 3,
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: currentPreviewAsset != null
                                  ? Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        // 基础罗盘图
                                        AppAssetImage(
                                          assetPath: currentPreviewAsset!,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return Container(
                                              color: Colors.grey[200],
                                              child: const Icon(
                                                Icons.image_not_supported,
                                                color: Colors.grey,
                                                size: 40,
                                              ),
                                            );
                                          },
                                        ),
                                        // 圈内图片（叠加在罗盘图上）
                                        if (innerSegments > 0)
                                          Builder(
                                            builder: (context) {
                                              final innerPath = _buildInnerRingImagePath(
                                                innerSegments,
                                                add24Mountains,
                                                addBagua,
                                                add360,
                                              );
                                              if (innerPath == null) {
                                                return const SizedBox.shrink();
                                              }
                                              return AppAssetImage(
                                                assetPath: innerPath,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) {
                                                  debugPrint('圈内图片加载失败: $innerPath');
                                                  return const SizedBox.shrink();
                                                },
                                              );
                                            },
                                          ),
                                        // 圈外图片（叠加在罗盘图上）
                                        if (outerSegments > 0)
                                          Builder(
                                            builder: (context) {
                                              final outerPath = _buildOuterRingImagePath(outerSegments);
                                              if (outerPath == null) {
                                                return const SizedBox.shrink();
                                              }
                                              return AppAssetImage(
                                                assetPath: outerPath,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) {
                                                  debugPrint('圈外图片加载失败: $outerPath');
                                                  return const SizedBox.shrink();
                                                },
                                              );
                                            },
                                          ),
                                      ],
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // 圈内
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '圈内',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 24,
                            children: [
                              _buildRadioChip(
                                dialogCtx,
                                label: '无格',
                                selected: innerSegments == 0,
                                onTap: () => setDialogState(() {
                                  innerSegments = 0;
                                  // 预览图会自动更新（因为 innerSegments 改变了）
                                }),
                              ),
                              _buildRadioChip(
                                dialogCtx,
                                label: '8格',
                                selected: innerSegments == 8,
                                onTap: () => setDialogState(() {
                                  innerSegments = 8;
                                  // 预览图会自动更新（因为 innerSegments 改变了）
                                }),
                              ),
                              _buildRadioChip(
                                dialogCtx,
                                label: '12格',
                                selected: innerSegments == 12,
                                onTap: () => setDialogState(() {
                                  innerSegments = 12;
                                  // 预览图会自动更新（因为 innerSegments 改变了）
                                }),
                              ),
                              _buildRadioChip(
                                dialogCtx,
                                label: '24格',
                                selected: innerSegments == 24,
                                onTap: () => setDialogState(() {
                                  innerSegments = 24;
                                  // 预览图会自动更新（因为 innerSegments 改变了）
                                }),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 圈外
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '圈外',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 24,
                            children: [
                              _buildRadioChip(
                                dialogCtx,
                                label: '无格',
                                selected: outerSegments == 0,
                                onTap: () => setDialogState(() {
                                  outerSegments = 0;
                                  // 预览图会自动更新（因为 outerSegments 改变了）
                                }),
                              ),
                              _buildRadioChip(
                                dialogCtx,
                                label: '8格',
                                selected: outerSegments == 8,
                                onTap: () => setDialogState(() {
                                  outerSegments = 8;
                                  // 预览图会自动更新（因为 outerSegments 改变了）
                                }),
                              ),
                              _buildRadioChip(
                                dialogCtx,
                                label: '12格',
                                selected: outerSegments == 12,
                                onTap: () => setDialogState(() {
                                  outerSegments = 12;
                                  // 预览图会自动更新（因为 outerSegments 改变了）
                                }),
                              ),
                              _buildRadioChip(
                                dialogCtx,
                                label: '24格',
                                selected: outerSegments == 24,
                                onTap: () => setDialogState(() {
                                  outerSegments = 24;
                                  // 预览图会自动更新（因为 outerSegments 改变了）
                                }),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 附加层
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '附加层',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              FilterChip(
                                label: const Text(
                                  '二十四山',
                                  style: TextStyle(fontSize: 12),
                                ),
                                labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                selected: add24Mountains,
                                onSelected: (v) {
                                  setDialogState(() {
                                    add24Mountains = v;
                                    // 更新预览图路径（使用更新后的值）
                                    if (previewAsset != null) {
                                      currentPreviewAsset = _buildCompassImagePath(
                                        previewAsset!,
                                        v, // 使用新的值
                                        addBagua,
                                        add360,
                                      );
                                    }
                                  });
                                },
                              ),
                              FilterChip(
                                label: const Text(
                                  '八卦',
                                  style: TextStyle(fontSize: 12),
                                ),
                                labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                selected: addBagua,
                                onSelected: (v) {
                                  setDialogState(() {
                                    addBagua = v;
                                    // 更新预览图路径（使用更新后的值）
                                    if (previewAsset != null) {
                                      currentPreviewAsset = _buildCompassImagePath(
                                        previewAsset!,
                                        add24Mountains,
                                        v, // 使用新的值
                                        add360,
                                      );
                                    }
                                  });
                                },
                              ),
                              FilterChip(
                                label: const Text(
                                  '360度',
                                  style: TextStyle(fontSize: 12),
                                ),
                                labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                selected: add360,
                                onSelected: (v) {
                                  setDialogState(() {
                                    add360 = v;
                                    // 更新预览图路径（使用更新后的值）
                                    if (previewAsset != null) {
                                      currentPreviewAsset = _buildCompassImagePath(
                                        previewAsset!,
                                        add24Mountains,
                                        addBagua,
                                        v, // 使用新的值
                                      );
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.red),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () => Navigator.of(dialogCtx).pop(),
                              child: const Text(
                                '取消',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: SizedBox(
                            height: 44,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () async {
                                debugPrint('制作立极尺：点击确定');
                                final name = controller.text.trim().isEmpty
                                    ? defaultName
                                    : controller.text.trim();

                                // 未登录：提示并跳转登录
                                if (!AuthService.isLoggedIn) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('当前未登录，无法添加立极尺')),
                                  );
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const LoginPage(),
                                    ),
                                  );
                                  // 登录返回后再次检查
                                  if (!AuthService.isLoggedIn) {
                                    return;
                                  }
                                }

                                // 安全获取当前用户和 userId，避免 null -> int 的类型错误
                                final authUser = AuthService.currentUser.value;
                                final int userId = authUser?.userId ?? 0;

                                if (userId == 0) {
                                  // 认为 userId=0 为无效用户，提示重新登录
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('用户信息异常，请重新登录')),
                                  );
                                  await AuthService.logout();
                                  return;
                                }

                                // 已登录且 userId 有效：调用后端保存
                                try {
                                  final body = {
                                    'userId': userId,
                                    'name': name,
                                    // 使用当前预览图路径作为基础罗盘资源；
                                    // 如果用户勾选了“二十四山/八卦/360度”，
                                    // 对于诸如“人盘正兼向度数（9度内）1”这类模板，
                                    // 就会生成类似 “二十四山-八卦-360度.png” 这样的组合文件。
                                    'baseAsset': currentPreviewAsset ??
                                        previewAsset ??
                                        'assets/liji/JiuXingFanGua.png',
                                    'innerSegments': innerSegments,
                                    'outerSegments': outerSegments,
                                    'add24Mountains': add24Mountains,
                                    'addBagua': addBagua,
                                    'add360': add360,
                                  };

                                  debugPrint('POST $_baseUrl/cp/lijiTemplate body=$body');

                                  final resp = await http.post(
                                    Uri.parse('$_baseUrl/cp/lijiTemplate'),
                                    headers: {
                                      'Content-Type': 'application/json; charset=utf-8',
                                      'Authorization': 'Bearer ${authUser!.token}',
                                    },
                                    body: json.encode(body),
                                  );

                                  debugPrint(
                                      '保存立极尺 resp.status=${resp.statusCode} body=${resp.body}');

                                  if (resp.statusCode == 200) {
                                    final data = json.decode(resp.body);
                                    if (data is Map &&
                                        (data['code'] == 200 || data['code'] == '200')) {
                                      final tpl = data['data'] as Map<String, dynamic>?;
                                      final baseAsset = tpl?['baseAsset'] != null
                                          ? tpl!['baseAsset'].toString()
                                          : body['baseAsset'].toString();
                                      // 解析后端返回的圈内/圈外和附加层配置
                                      int _parseInt(dynamic v) {
                                        if (v == null) return 0;
                                        if (v is int) return v;
                                        return int.tryParse(v.toString()) ?? 0;
                                      }

                                      bool _parseBool(dynamic v) {
                                        if (v == null) return false;
                                        if (v is bool) return v;
                                        final s = v.toString().toLowerCase();
                                        return s == 'true' || s == '1';
                                      }

                                      final int innerSegments =
                                          _parseInt(tpl?['innerSegments'] ?? body['innerSegments']);
                                      final int outerSegments =
                                          _parseInt(tpl?['outerSegments'] ?? body['outerSegments']);
                                      final bool add24Mountains = _parseBool(
                                          tpl?['add24Mountains'] ?? body['add24Mountains']);
                                      final bool addBagua =
                                          _parseBool(tpl?['addBagua'] ?? body['addBagua']);
                                      final bool add360 =
                                          _parseBool(tpl?['add360'] ?? body['add360']);

                                      setState(() {
                                        _userTemplates.add(
                                          _LijiTemplate(
                                            englishFile: '',
                                            chineseFile: '',
                                            displayName: name,
                                            assetPath: baseAsset,
                                            innerSegments: innerSegments,
                                            outerSegments: outerSegments,
                                            add24Mountains: add24Mountains,
                                            addBagua: addBagua,
                                            add360: add360,
                                            isUserTemplate: true,
                                          ),
                                        );
                                      });
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('立极尺已保存')),
                                      );
                                      // 依次关闭“制作立极尺”对话框和其下方的“添加立极尺”抽屉
                                      if (Navigator.of(context).canPop()) {
                                        Navigator.of(context).pop(); // 关闭对话框
                                      }
                                      if (Navigator.of(context).canPop()) {
                                        Navigator.of(context).pop(); // 关闭下方抽屉
                                      }
                                      // 然后重新打开“选择立极尺罗盘”抽屉（内部会重新加载自定义模板数据）
                                      await _showLijiTemplateSheet(context);
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              '保存失败：${data['msg'] ?? '未知错误'}'),
                                        ),
                                      );
                                    }
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content:
                                            Text('保存失败，状态码：${resp.statusCode}'),
                                      ),
                                    );
                                  }
                                } catch (e, s) {
                                  debugPrint('保存立极尺异常：$e\n$s');
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('保存异常：$e')),
                                  );
                                }
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
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// 显示"保存"抽屉（保存到相册 / 发送测量）
  void _showSaveSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: 220,
            child: Column(
              children: [
                const SizedBox(height: 4),
                _buildSheetDownCloseButton(context),
                const SizedBox(height: 4),
                const Divider(height: 1),
                // 保存测量到相册
                ListTile(
                  leading: const Icon(Icons.download_outlined, size: 28),
                  title: const Text(
                    '保存测量到相册',
                    style: TextStyle(fontSize: 18),
                  ),
                  onTap: () {
                    Navigator.of(context).pop(); // 关闭当前抽屉
                    _showSaveResultSheet(
                      this.context,
                      isShare: false,
                    );
                  },
                ),
                const Divider(height: 1),
                // 发送测量
                ListTile(
                  leading: const Icon(Icons.reply_outlined, size: 28),
                  title: const Text(
                    '发送测量',
                    style: TextStyle(fontSize: 18),
                  ),
                  onTap: () {
                    Navigator.of(context).pop(); // 关闭当前抽屉
                    _showSaveResultSheet(
                      this.context,
                      isShare: true,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 构建当前默认的图片注释（优先使用九运玄空风水提示）
  String _buildCurrentAnnotation() {
    if (_currentLuckIndex != null &&
        _currentLuckIndex! >= 0 &&
        _currentLuckIndex! < _nineLuckHints.length) {
      final hint = _nineLuckHints[_currentLuckIndex!];
      return '${hint.title} ${hint.detail}';
    }
    return '';
  }

  /// 显示“保存测量结果图片”二级抽屉（可编辑注释）
  void _showSaveResultSheet(BuildContext context, {required bool isShare}) {
    final defaultText = _buildCurrentAnnotation();
    final controller = TextEditingController(text: defaultText);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 280,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 12),
                  // 顶部标题 + 关闭按钮
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const SizedBox(width: 40), // 占位，保证标题居中
                        Text(
                          isShare ? '发送测量结果图片' : '保存测量结果图片',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(ctx).pop(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // “在图片上添加注释” 文本
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      '在图片上添加注释',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 注释输入框
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF7F7F7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: TextField(
                        controller: controller,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 15),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  // 底部保存按钮
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SizedBox(
                      height: 52,
                       child: ElevatedButton(
                         onPressed: () async {
                           final text = controller.text.trim();
                           if (!isShare) {
                             await _saveMeasurementToAlbum(annotation: text);
                           } else {
                              await _shareMeasurement(annotation: text);
                           }
                           if (ctx.mounted) Navigator.of(ctx).pop();
                         },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          side: const BorderSide(
                            color: Color(0xFFEE7C2F),
                            width: 1.2,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                         child: Text(
                          isShare ? '发送' : '保存',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).whenComplete(() {
      controller.dispose();
    });
  }

  /// 显示“九运”抽屉
  void _showNineLuckSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSheetTopBar(context, title: '玄空飞星'),
                const Divider(height: 1),
                // 九运列表
                Expanded(
                  child: ListView.separated(
                    itemCount: _nineLuckPeriods.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final text = _nineLuckPeriods[index];
                      final selected = _currentLuckIndex == index;
                      return ListTile(
                        title: Text(
                          text,
                          style: TextStyle(
                            fontSize: 16,
                            color: selected ? Colors.red : Colors.black87,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                        trailing: selected
                            ? const Icon(Icons.check, color: Colors.red)
                            : null,
                        onTap: () {
                          // 选中对应九运，并在主页面显示提示信息
                          setState(() {
                            _currentLuckIndex = index;
                            _useNineLuckCompass = true; // 使用九运罗盘
                          });
                          Navigator.of(context).pop();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 显示“选项”抽屉
  void _showOptionsSheet(BuildContext context) {
    // 打开选项面板时，同步滑动条的初始值为当前显示的方向度数
    _lijiAngleDeg = _headingDegreesForDisplay;

    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return SafeArea(
              top: false,
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),
                      // 顶部小拖拽条
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: _buildSheetDownCloseButton(context),
                      ),
                      const SizedBox(height: 8),

                      // 天心十道 & 深色模式
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  '天心十道',
                                  style: TextStyle(fontSize: 16),
                                ),
                                const SizedBox(width: 8),
                                Switch(
                                  value: _tianXinShiDaoEnabled,
                                  onChanged: (v) {
                                    modalSetState(() {
                                      _tianXinShiDaoEnabled = v;
                                    });
                                    setState(() {
                                      _tianXinShiDaoEnabled = v;
                                    });
                                  },
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Text(
                                  '深色模式',
                                  style: TextStyle(fontSize: 16),
                                ),
                                const SizedBox(width: 8),
                                Switch(
                                  value: _darkModeEnabled,
                                  onChanged: (v) {
                                    modalSetState(() {
                                      _darkModeEnabled = v;
                                    });
                                    setState(() {
                                      _darkModeEnabled = v;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // 立极尺角度（与当前方向度数同步）
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Text(
                                  '立极尺角度',
                                  style: TextStyle(fontSize: 16),
                                ),
                                const SizedBox(width: 16),
                                SizedBox(
                                  width: 72,
                                  child: Text(
                                    '${_lijiAngleDeg.toStringAsFixed(1)}°',
                                    textAlign: TextAlign.right,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Text('锁定'),
                                const SizedBox(width: 4),
                                Checkbox(
                                  value: _isLijiLocked,
                                  onChanged: (v) {
                                    modalSetState(() {
                                      _isLijiLocked = v ?? false;
                                    });
                                    setState(() {
                                      _isLijiLocked = v ?? false;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                        Slider(
                          value: _lijiAngleDeg,
                          min: 0,
                          max: 360,
                          onChanged: _isLijiLocked
                              ? null
                              : (v) {
                                  modalSetState(() {
                                    _lijiAngleDeg = v;
                                  });
                                  setState(() {
                                    _lijiAngleDeg = v;
                                    // 将滑动条角度同步回当前方向度数（与标题同一体系）
                                    final targetHeading = v;
                                    double targetDeg =
                                        (targetHeading - 180) % 360;
                                    if (targetDeg < 0) targetDeg += 360;
                                    _rotation = -targetDeg * pi / 180.0;
                                  });
                                },
                        ),
                      ],
                    ),
                  ),

                      // 立极尺透明度
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '立极尺透明度',
                              style: TextStyle(fontSize: 16),
                            ),
                            Slider(
                              value: _lijiOpacity,
                              min: 0.1,
                              max: 1.0,
                              onChanged: (v) {
                                modalSetState(() {
                                  _lijiOpacity = v;
                                });
                                setState(() {
                                  _lijiOpacity = v;
                                });
                              },
                            ),
                          ],
                        ),
                      ),

                      // 底图角度
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            const Text(
                              '底图角度',
                              style: TextStyle(fontSize: 16),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Slider(
                                value: _backgroundAngleDeg,
                                min: 0,
                                max: 360,
                                onChanged: (v) {
                                  modalSetState(() {
                                    _backgroundAngleDeg = v;
                                  });
                                  setState(() {
                                    _backgroundAngleDeg = v;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 72,
                              child: Text(
                                '${_backgroundAngleDeg.toStringAsFixed(1)}°',
                                textAlign: TextAlign.right,
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 辅助线选项
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  value: _auxLine1,
                                  onChanged: (v) {
                                    modalSetState(() {
                                      _auxLine1 = v ?? false;
                                    });
                                    setState(() {
                                      _auxLine1 = v ?? false;
                                    });
                                  },
                                ),
                                const Text('辅助线1'),
                              ],
                            ),
                            Row(
                              children: [
                                Checkbox(
                                  value: _auxLine2,
                                  onChanged: (v) {
                                    modalSetState(() {
                                      _auxLine2 = v ?? false;
                                    });
                                    setState(() {
                                      _auxLine2 = v ?? false;
                                    });
                                  },
                                ),
                                const Text('辅助线2'),
                              ],
                            ),
                            Row(
                              children: [
                                Checkbox(
                                  value: _auxLine3,
                                  onChanged: (v) {
                                    modalSetState(() {
                                      _auxLine3 = v ?? false;
                                    });
                                    setState(() {
                                      _auxLine3 = v ?? false;
                                    });
                                  },
                                ),
                                const Text('辅助线3'),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 显示“底图”抽屉（选择来源 + 调整底图角度）
  void _showBackgroundSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            return SafeArea(
              top: false,
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.55,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    // 顶部小拖拽条 + 下拉箭头（与截图一致）
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _buildSheetDownCloseButton(context),
                    const SizedBox(height: 4),
                    const Divider(height: 1),

                    // 资源选择
                    ListTile(
                      leading: const Icon(Icons.image_outlined),
                      title: const Text('本地相册',
                          style: TextStyle(fontSize: 18)),
                      onTap: () async {
                        Navigator.of(context).pop(); // 先关闭底图抽屉

                        try {
                          final path =
                              await GalleryImagePicker.pickImagePath();
                          if (path != null) {
                            setState(() {
                              _imageBackgroundFile = File(path);
                              // 选择本地相册/相机时，清空地图底图
                              _mapBackground = null;
                            });
                          }
                        } on PlatformException catch (e) {
                          if (!mounted) return;
                          final msg = e.message ??
                              (e.code == 'native_not_available'
                                  ? '请完全退出应用后重新运行（Stop → Run）'
                                  : '选择图片失败');
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(content: Text(msg)),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(content: Text('选择图片失败: $e')),
                          );
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.photo_camera_outlined),
                      title: const Text('相机', style: TextStyle(fontSize: 18)),
                      onTap: () async {
                        Navigator.of(context).pop(); // 先关闭底图抽屉

                        try {
                          final XFile? picked = await _imagePicker.pickImage(
                            source: ImageSource.camera,
                          );
                          if (picked != null) {
                            setState(() {
                              _imageBackgroundFile = File(picked.path);
                              // 使用相机拍照时，同样清空地图底图
                              _mapBackground = null;
                            });
                          }
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(content: Text('拍照失败: $e')),
                          );
                        }
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.map_outlined),
                      title: const Text('地图', style: TextStyle(fontSize: 18)),
                      onTap: () async {
                        Navigator.of(context).pop(); // 先关闭底图抽屉

                        final selection = await Navigator.of(this.context).push(
                          MaterialPageRoute(
                            builder: (_) => TiandituPickMapPage(
                              initialCenter: _mapBackground?.center,
                              initialZoom: _mapBackground?.zoom ?? 16,
                              initialSatellite:
                                  _mapBackground?.isSatellite ?? false,
                            ),
                          ),
                        );

                        if (!mounted) return;
                        if (selection is TiandituMapSelection) {
                          setState(() {
                            _mapBackground = selection;
                            // 与相册/相机互斥：选用地图底图时清除本地图片底图
                            _imageBackgroundFile = null;
                          });
                        }
                      },
                    ),

                    const Spacer(),

                    // 底图角度 + 旋转90°
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                      child: Row(
                        children: [
                          const Text('底图角度',
                              style: TextStyle(fontSize: 16)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${_backgroundAngleDeg.toStringAsFixed(1)}°',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                          InkWell(
                            onTap: () {
                              modalSetState(() {
                                _backgroundAngleDeg =
                                    (_backgroundAngleDeg + 90) % 360;
                              });
                              setState(() {
                                _backgroundAngleDeg =
                                    (_backgroundAngleDeg + 90) % 360;
                              });
                            },
                            child: Row(
                              children: const [
                                Icon(Icons.refresh, size: 18),
                                SizedBox(width: 6),
                                Text('旋转90°',
                                    style: TextStyle(fontSize: 16)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 角度滑条
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Slider(
                        value: _backgroundAngleDeg,
                        min: 0,
                        max: 360,
                        onChanged: (v) {
                          modalSetState(() {
                            _backgroundAngleDeg = v;
                          });
                          setState(() {
                            _backgroundAngleDeg = v;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _OperationHelpContent extends StatelessWidget {
  const _OperationHelpContent();

  @override
  Widget build(BuildContext context) {
    const sectionTitleStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      color: Colors.black87,
    );
    const bodyStyle = TextStyle(
      fontSize: 16,
      height: 1.7,
      color: Colors.black54,
    );

    Widget section(String title, List<String> lines) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: sectionTitleStyle),
            const SizedBox(height: 10),
            Text(lines.join('\n'), style: bodyStyle),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        section('一. 立极尺', const [
          '1. 单指在立极尺内滑动，可拖动立极尺',
          '2. 单指按住左上、右上、左下、右下缩放按钮拖动，可缩放立极尺',
          '3. 单指在立极尺外的圆环滑动，可旋转立极尺',
        ]),
        section('二. 视图', const [
          '1. 双指张合可放大缩小整个视图',
          '2. 当视图放大后，双指在立极尺内滑动，可移动整个视图',
          '（注：对视图的缩放或平移属于查看操作，对测量结果没有影响）',
        ]),
        section('三. 辅助线', const [
          '1. 单指点中辅助线滑动，可单独旋转辅助线',
          '（注：辅助线需在选项中开启显示）',
        ]),
      ],
    );
  }
}

/// 绘制通过中心的水平和垂直红线
class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red 
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);

    // 垂直线
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      paint,
    );

    // 水平线
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 绘制三条可旋转的辅助线（红/绿/蓝）
class _AuxLinesPainter extends CustomPainter {
  _AuxLinesPainter({
    required this.compassDiameter,
    required this.angle1,
    required this.angle2,
    required this.angle3,
    required this.show1,
    required this.show2,
    required this.show3,
  });

  final double compassDiameter;
  final double angle1;
  final double angle2;
  final double angle3;
  final bool show1;
  final bool show2;
  final bool show3;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = compassDiameter / 2;

    void drawArrow(Color color, double angle) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      final dir = Offset(cos(angle), sin(angle));
      // 贯穿整个直径：从一侧穿过圆心到另一侧
      final start = center - dir * radius;
      final end = center + dir * radius;

      // 主线
      canvas.drawLine(start, end, paint);

      // 箭头
      const arrowSize = 10.0;
      final ortho = Offset(-dir.dy, dir.dx);
      final tip = end;
      final left = tip - dir * arrowSize + ortho * (arrowSize * 0.6);
      final right = tip - dir * arrowSize - ortho * (arrowSize * 0.6);
      final path = Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(left.dx, left.dy)
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(right.dx, right.dy);
      canvas.drawPath(path, paint);
    }

    if (show1) {
      drawArrow(Colors.red, angle1);
    }
    if (show2) {
      drawArrow(Colors.green, angle2);
    }
    if (show3) {
      drawArrow(Colors.blue, angle3);
    }
  }

  @override
  bool shouldRepaint(covariant _AuxLinesPainter oldDelegate) {
    return compassDiameter != oldDelegate.compassDiameter ||
        angle1 != oldDelegate.angle1 ||
        angle2 != oldDelegate.angle2 ||
        angle3 != oldDelegate.angle3 ||
        show1 != oldDelegate.show1 ||
        show2 != oldDelegate.show2 ||
        show3 != oldDelegate.show3;
  }
}

/// 单选圆形样式的辅助组件（用于“圈内/圈外”单选项）
Widget _buildRadioChip(
  BuildContext context, {
  required String label,
  required bool selected,
  required VoidCallback onTap,
}) {
  return InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: onTap,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
          color: selected ? Colors.red : Colors.grey,
          size: 20,
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: selected ? Colors.red : Colors.black87,
          ),
        ),
      ],
    ),
  );
}

/// 绘制红色虚线矩形边框
class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({
    required this.color,
    this.strokeWidth = 1.0,
    this.dashLength = 6.0,
    this.dashGap = 4.0,
    this.radius = 0.0,
  });

  final Color color;
  final double strokeWidth;
  final double dashLength;
  final double dashGap;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final path = Path()..addRRect(rrect);

    for (final metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashLength;
        final extractPath = metric.extractPath(
          distance,
          next.clamp(0.0, metric.length),
        );
        canvas.drawPath(extractPath, paint);
        distance += dashLength + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 九运提示数据结构
class _LuckHint {
  final String title;
  final String detail;

  const _LuckHint({
    required this.title,
    required this.detail,
  });
}


/// 立极尺模板元数据：拼音文件名 + 中文文件名 + 展示名称 +（自定义时）圈内/圈外/附加层配置
class _LijiTemplate {
  final String englishFile; // 不含路径和扩展名，例如 BaGeBaGua
  final String chineseFile; // 不含扩展名，例如 八格八卦
  final String displayName; // 页面显示的中文名称
  final String? assetPath; // 自定义模板时使用的完整基础罗盘资源路径

  /// 以下字段主要用于“自定义模板”，用于还原圈内/圈外格数和附加层
  final int innerSegments; // 圈内格数（0/8/12/24）
  final int outerSegments; // 圈外格数（0/8/12/24）
  final bool add24Mountains; // 是否叠加二十四山
  final bool addBagua; // 是否叠加八卦
  final bool add360; // 是否叠加360度刻度
  final bool isUserTemplate; // 是否为用户自定义模板

  const _LijiTemplate({
    required this.englishFile,
    required this.chineseFile,
    required this.displayName,
    this.assetPath,
    this.innerSegments = 0,
    this.outerSegments = 0,
    this.add24Mountains = false,
    this.addBagua = false,
    this.add360 = false,
    this.isUserTemplate = false,
  });
}

/// 绘制沿圆周排列的文字
class _CircularTextPainter extends CustomPainter {
  _CircularTextPainter({
    required this.text,
    required this.radius,
  });

  final String text;
  // 文字所在圆周的半径（固定在圆环上，随圆环缩放）
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // 使用半径绘制文字，文字固定在圆环上
    final textRadius = radius;

    // 创建文字样式
    final textStyle = const TextStyle(
      fontSize: 12,
      color: Colors.black87,
      fontWeight: FontWeight.w500,
    );

    // 使用 TextPainter 测量文字
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // 计算文字在圆周上的起始角度（从顶部开始，逆时针排列）
    // 文字总长度对应的角度
    final textWidth = textPainter.width;
    final textAngle = textWidth / textRadius;

    // 起始角度：从顶部（-90度）开始，减去文字角度的一半，使文字居中
    final startAngle = -pi / 2 - textAngle / 2;

    // 将每个字符绘制在圆周上
    double currentAngle = startAngle;
    for (int i = 0; i < text.length; i++) {
      final char = text[i];

      // 测量单个字符的宽度
      final charPainter = TextPainter(
        text: TextSpan(text: char, style: textStyle),
        textDirection: TextDirection.ltr,
      );
      charPainter.layout();

      final charWidth = charPainter.width;
      final charAngle = charWidth / textRadius;

      // 计算字符中心位置的角度
      final charCenterAngle = currentAngle + charAngle / 2;

      // 计算字符在圆周上的位置
      final charX = center.dx + textRadius * cos(charCenterAngle);
      final charY = center.dy + textRadius * sin(charCenterAngle);

      // 保存画布状态
      canvas.save();

      // 移动到字符位置并旋转
      canvas.translate(charX, charY);
      canvas.rotate(charCenterAngle + pi / 2); // +pi/2 使文字沿圆周方向

      // 绘制字符（需要偏移到字符中心）
      charPainter.paint(
        canvas,
        Offset(-charWidth / 2, -charPainter.height / 2),
      );

      // 恢复画布状态
      canvas.restore();

      // 更新当前角度
      currentAngle += charAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _CircularTextPainter oldDelegate) {
    return oldDelegate.radius != radius || oldDelegate.text != text;
  }
}

/// 从系统相册选一张图。Android 走原生通道直接调起系统图库 App。
class GalleryImagePicker {
  static const MethodChannel _channel = MethodChannel('liji_image_saver');

  static Future<String?> pickImagePath() async {
    if (Platform.isAndroid) {
      try {
        final path =
            await _channel.invokeMethod<String>('pickImageFromGallery');
        if (path != null && path.isNotEmpty) return path;
        return null;
      } on MissingPluginException {
        throw PlatformException(
          code: 'native_not_available',
          message: '请完全退出应用后重新运行（Stop → Run），以打开系统图库',
        );
      } on PlatformException catch (e) {
        if (e.code == 'NO_GALLERY' || e.code == 'LAUNCH_FAILED') {
          // 鸿蒙等机型原生通道失败时，回退 image_picker
          final picked = await ImagePicker().pickImage(
            source: ImageSource.gallery,
          );
          return picked?.path;
        }
        rethrow;
      }
    }
    final XFile? picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
    );
    return picked?.path;
  }
}
