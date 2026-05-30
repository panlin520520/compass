import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'compass_page.dart';
import 'map_compass_page.dart';
import 'auth_service.dart';
import 'measure_record_pages.dart';
import 'utils/asset_rotation.dart';
import 'api_config.dart';
import 'default_tip_json_catalog.dart';
/// 智能提示底部详情：金棕标题 + 深灰正文。
class OtherTipResolved {
  const OtherTipResolved({required this.title, required this.body});

  final String title;
  final String body;
}

/// 智能提示 [assets/other-tip-json]：优先 **ASCII** 合并包 [assets/other_tip_layers.json]（与 [DefaultTipJsonCatalog] 一致），
/// 失败后再按 index.json + 显式路径逐个加载。
class OtherTipJsonCatalog {
  OtherTipJsonCatalog._();

  /// 纯 ASCII 路径，避免中文文件名在部分平台上无法从 AssetBundle 加载。
  static const String _packedAssetPath = 'assets/other_tip_layers.json';

  static const String _otherTipFolderPrefix = 'assets/other-tip-json/';
  static const String _otherTipIndexPath = 'assets/other-tip-json/index.json';

  static const List<String> _otherTipExplicitPaths = <String>[
    'assets/other-tip-json/分金提示.json',
    'assets/other-tip-json/二十四山宜忌.json',
    'assets/other-tip-json/金锁玉关.json',
    'assets/other-tip-json/纳甲辅星水法.json',
    'assets/other-tip-json/二十四山向.json',
    'assets/other-tip-json/山水六十龙.json',
    'assets/other-tip-json/二十四位水法诀.json',
    'assets/other-tip-json/二十四山砂水断语.json',
    'assets/other-tip-json/五行提示.json',
    'assets/other-tip-json/二十四山砂.json',
  ];

  static Future<String?> _otherTipLoadUtf8(String logicalPath) async {
    final norm = Uri.decodeFull(logicalPath.replaceAll('\\', '/'));
    return loadAppAssetString(norm);
  }

  static Future<List<String>> _otherTipEnumerateJsonPaths() async {
    final out = <String>[];

    final indexText = await _otherTipLoadUtf8(_otherTipIndexPath);
    if (indexText != null) {
      try {
        final list = json.decode(indexText) as List<dynamic>;
        for (final e in list) {
          if (e is! String) continue;
          if (!e.toLowerCase().endsWith('.json')) continue;
          if (e == 'index.json') continue;
          out.add('$_otherTipFolderPrefix$e');
        }
      } catch (_) {}
    }

    if (out.isNotEmpty) {
      out.sort();
      return out;
    }

    for (final p in _otherTipExplicitPaths) {
      out.add(p);
    }
    out.sort();
    return out;
  }

  /// 主入口：先读合并包，失败再尝试分散 JSON。
  static Future<List<OtherTipJsonEntry>> load() async {
    final packed = await _otherTipLoadUtf8(_packedAssetPath);
    if (packed != null) {
      try {
        final map = json.decode(packed) as Map<String, dynamic>;
        final out = <OtherTipJsonEntry>[];
        for (final e in map.entries) {
          out.add(OtherTipJsonEntry(displayName: e.key, root: e.value));
        }
        out.sort((a, b) => a.displayName.compareTo(b.displayName));
        if (out.isNotEmpty) return out;
      } catch (_) {}
    }

    return _loadFromSeparateFiles();
  }

  static Future<List<OtherTipJsonEntry>> _loadFromSeparateFiles() async {
    final paths = await _otherTipEnumerateJsonPaths();
    final out = <OtherTipJsonEntry>[];
    for (final logical in paths) {
      final raw = await _otherTipLoadUtf8(logical);
      if (raw == null) continue;
      try {
        final decoded = json.decode(raw);
        final file = logical.split('/').last;
        final name =
            file.endsWith('.json') ? file.substring(0, file.length - 5) : file;
        out.add(OtherTipJsonEntry(displayName: name, root: decoded));
      } catch (_) {}
    }
    out.sort((a, b) => a.displayName.compareTo(b.displayName));
    return out;
  }
}

class OtherTipJsonEntry {
  OtherTipJsonEntry({
    required this.displayName,
    required this.root,
  });

  final String displayName;
  final dynamic root;
}

class CompassDetailPage extends StatefulWidget {
  final String compassImagePath;
  final VoidCallback? onMenuPressed;
  final String? backgroundImagePath;
  /// 智能读盘或实景罗盘开启时通知外层隐藏首页底部导航栏。
  final ValueChanged<bool>? onSmartTipModeChanged;

  const CompassDetailPage({
    super.key,
    required this.compassImagePath,
    this.onMenuPressed,
    this.backgroundImagePath,
    this.onSmartTipModeChanged,
  });

  @override
  State<CompassDetailPage> createState() => _CompassDetailPageState();
}

class _CompassDetailPageState extends State<CompassDetailPage> with SingleTickerProviderStateMixin {
  static const double _longmenBajuOverlayScale = 1;

  double _heading = 0.0; // 指南针方向（度）
  double _pitch = 0.0; // 俯仰角（前后倾斜）
  double _roll = 0.0; // 横滚角（左右倾斜）

  // 平滑处理用的目标值
  double _targetHeading = 0.0;
  /// 实时磁北方位（指针用，锁定盘面时仍更新）
  double _liveMagneticHeading = 0.0;
  double _targetPitch = 0.0;
  double _targetRoll = 0.0;

  bool _isLocked = false;
  double _lockedHeading = 0.0;
  double _compassRotationOffset = 0.0; // 罗盘旋转偏移角度（度）
  bool _showRotationPanel = false; // 是否显示旋转调整面板
  bool _isCameraEnabled = false; // 是否启用摄像头
  CameraController? _cameraController;
  List<CameraDescription>? _cameras;

  late AnimationController _animationController;

  // 位置和海拔相关
  double? _latitude;
  double? _longitude;
  double? _altitude;
  double? _pressure; // 气压（hPa）
  double? _seaLevelPressure; // 海平面气压（hPa）
  bool _isLoadingLocation = false;
  bool _isLoadingAltitude = false;
  String? _address; // 测量地点
  StateSetter? _sheetStateSetter; // 用于更新抽屉状态

  /// 「智能提示」侧栏 [StatefulBuilder] 的 setState；异步加载 other-tip 完成后需调用，否则弹层内列表不刷新。
  StateSetter? _smartTipsDrawerStateSetter;

  // 罗盘缩放/拖动相关
  final TransformationController _compassTransformController =
      TransformationController();

  // 罗盘透明度（只影响罗盘叠加层，不影响实景背景）
  double _compassOpacity = 1.0;
  bool _useBlackLine = false; // 实景罗盘附加线条：false=白线条，true=黑线条

  // 测量记录备注
  final TextEditingController _measureRemarkController = TextEditingController();
  bool _isSavingMeasureRecord = false;

  static const String _baseUrl = kApiBaseUrl;

  // 新手指引相关
  bool _showZoomGuide = false; // 是否显示“放大”指引 GIF
  bool _showDragGuide = false; // 是否显示“拖动”指引 GIF
  Timer? _zoomGuideTimer;
  Timer? _dragGuideTimer;

  // 设置抽屉相关
  bool _rotationSoundEnabled = false; // 声音振动
  bool _tianXinShiDaoEnabled = true; // 天心十道（预留，后续可用于显示辅助线）
  int? _lastRotationStep; // 上一次触发声音/振动的 3 度步进

  /// 当前智能提示：`null` 关闭，`default` 为默认多层提示，其余为 [assets/other-tip-json] 文件名（无后缀）。
  String? _smartTipKey;

  /// 派生自 [_smartTipKey]：重构删除字段后，避免热重载/调试器仍查找旧成员导致 Lookup failed。
  bool get _tipDefault => _smartTipKey == 'default';

  List<OtherTipJsonEntry> _otherTipEntries = [];
  bool _otherTipJsonLoaded = false;

  /// other-tip 详情：标题金棕、正文深灰（与设计稿一致）
  static const Color _kOtherTipDetailTitleColor = Color(0xFFC69C52);
  static const Color _kOtherTipDetailBodyColor = Color(0xFF333333);

  /// 与 [CompassPage] 一致：5 点环形移动平均，减少与指南针页读数差异
  final List<double> _headingHistory = [];
  static const int _headingHistorySize = 5;

  final GlobalKey _compassBodyStackKey = GlobalKey();
  final GlobalKey _compassHeaderKey = GlobalKey();
  final GlobalKey _smartTipCompassAreaKey = GlobalKey();
  final GlobalKey _smartTipPanelKey = GlobalKey();

  /// 默认提示抽屉：来自 assets/default_tip_layers.json（合并包）的解析结果
  List<DefaultTipJsonEntry> _defaultTipJsonEntries = [];
  bool _defaultTipJsonLoaded = false;

  void _notifyHomeBottomNavVisibility() {
    widget.onSmartTipModeChanged?.call(
      _smartTipKey != null || _isCameraEnabled,
    );
  }

  void _exitSmartTipMode() {
    if (_smartTipKey == null) return;
    setState(() => _smartTipKey = null);
    _notifyHomeBottomNavVisibility();
  }

  void _applySmartTipSwitch(String key, bool enabled) {
    setState(() {
      if (enabled) {
        _smartTipKey = key;
        if (key == 'default') {
          _defaultTipJsonLoaded = false;
          _defaultTipJsonEntries = [];
          _loadDefaultTipJsonEntries();
        }
      } else if (_smartTipKey == key) {
        _smartTipKey = null;
      }
    });
    _notifyHomeBottomNavVisibility();
    if (_smartTipKey != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      });
    }
  }

  /// 智能读盘内容区顶边：约为全屏高度一半，面板向下铺满至屏幕底（含原底部导航区域）。
  double _smartTipPanelTop(BuildContext context) {
    return MediaQuery.sizeOf(context).height * 0.48;
  }

  double _smartTipHeaderHeight() {
    final box =
        _compassHeaderKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) return box.size.height;
    return 48.0;
  }

  /// 按实际渲染位置计算：十字线（罗盘区垂直中心）对齐抽屉顶边。
  double _smartTipCompassTranslateOffset(
    BuildContext compassAreaContext,
    double compassAreaHeight,
  ) {
    final stackBox =
        _compassBodyStackKey.currentContext?.findRenderObject() as RenderBox?;
    final areaBox =
        compassAreaContext.findRenderObject() as RenderBox?;
    final panelBox =
        _smartTipPanelKey.currentContext?.findRenderObject() as RenderBox?;

    if (stackBox != null &&
        stackBox.hasSize &&
        areaBox != null &&
        areaBox.hasSize &&
        panelBox != null &&
        panelBox.hasSize) {
      final panelTop =
          panelBox.localToGlobal(Offset.zero, ancestor: stackBox).dy;
      final areaTop = areaBox.localToGlobal(Offset.zero, ancestor: stackBox).dy;
      return panelTop - areaTop - compassAreaHeight / 2;
    }

    // 首帧或未量到时的估算（略偏上，避免十字线落在抽屉下方）
    final mq = MediaQuery.of(compassAreaContext);
    final panelTop = _smartTipPanelTop(compassAreaContext);
    final headerH = _smartTipHeaderHeight();
    return panelTop -
        mq.padding.top -
        headerH -
        compassAreaHeight / 2 -
        12;
  }

  Widget _buildSmartTipCompassArea(double baseHeading) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final offsetY = _smartTipCompassTranslateOffset(
          context,
          constraints.maxHeight,
        );
        final crosshairY = constraints.maxHeight / 2 + offsetY;
        return Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Transform.translate(
                offset: Offset(0, offsetY),
                child: _buildCompass(baseHeading),
              ),
            ),
            if (_isCameraEnabled)
              Positioned(
                right: 16,
                top: (crosshairY - 52).clamp(8.0, double.infinity),
                child: _buildOpacityButton(),
              ),
            if (_showRotationPanel)
              Positioned(
                right: 16,
                top: 100,
                child: _buildRotationPanel(),
              ),
          ],
        );
      },
    );
  }

  Widget _buildSmartTipSheetShell({required Widget child}) {
    return Material(
      color: Colors.white,
      elevation: 10,
      shadowColor: Colors.black26,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.12),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  StreamSubscription<CompassEvent>? _compassSubscription;
  late StreamSubscription<AccelerometerEvent> _accelerometerSubscription;

  @override
  void initState() {
    super.initState();
    // 初始化动画控制器用于平滑过渡
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat();

    _animationController.addListener(() {
      if (mounted) {
        setState(() {
          // 使用线性插值平滑过渡到目标值
          final oldHeading = _heading;
          _heading = _smoothValue(_heading, _targetHeading);
          _pitch = _smoothValue(_pitch, _targetPitch);
          _roll = _smoothValue(_roll, _targetRoll);

          // 检查罗盘是否每转动 3 度需要触发一次声音和振动
          _checkRotationHaptics(oldHeading, _heading);
        });
      }
    });

    _startSensors();
    _initializeCamera();
    _loadDefaultTipJsonEntries();
    _loadOtherTipJsonEntries();
  }

  Future<void> _loadOtherTipJsonEntries() async {
    try {
      final list = await OtherTipJsonCatalog.load();
      if (!mounted) return;
      setState(() {
        _otherTipEntries = list;
        _otherTipJsonLoaded = true;
      });
      _smartTipsDrawerStateSetter?.call(() {});
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _otherTipEntries = [];
        _otherTipJsonLoaded = true;
      });
      _smartTipsDrawerStateSetter?.call(() {});
    }
  }

  Future<void> _loadDefaultTipJsonEntries() async {
    try {
      final list = await DefaultTipJsonCatalog.load();
      if (!mounted) return;
      setState(() {
        _defaultTipJsonEntries = list;
        _defaultTipJsonLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _defaultTipJsonEntries = [];
        _defaultTipJsonLoaded = true;
      });
    }
  }

  // 平滑值函数（低通滤波器）
  double _smoothValue(double current, double target) {
    // 使用0.15的平滑系数，值越小越平滑但响应越慢
    return current + (target - current) * 0.15;
  }

  double _normalizeDeg(double d) {
    double h = d % 360;
    if (h < 0) h += 360;
    return h;
  }

  /// 由向度数（朝向）求坐度数：向小于 180° 则 +180°，否则 -180°。
  double _sittingDegreeFromFacing(double facingDeg) {
    final h = _normalizeDeg(facingDeg);
    if (h < 180) return _normalizeDeg(h + 180);
    return h - 180;
  }

  /// 智能读盘抽屉顶栏：坐x向x + 向度数 + 坐度数。
  Widget _buildSmartTipHeadingSummaryRichText(double displayHeading) {
    final facingChar = _getSittingDirection(displayHeading);
    final sittingChar = _getOppositeSittingDirection(displayHeading);
    final facingDeg = _normalizeDeg(displayHeading);
    final sittingDeg = _sittingDegreeFromFacing(facingDeg);
    const labelStyle = TextStyle(
      color: Colors.black,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
    const valueStyle = TextStyle(
      color: Color(0xFF9C7A3F),
      fontSize: 13,
      fontWeight: FontWeight.w600,
      height: 1.25,
    );
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: '坐', style: labelStyle),
          TextSpan(text: sittingChar, style: valueStyle),
          const TextSpan(text: '向', style: labelStyle),
          TextSpan(text: facingChar, style: valueStyle),
          const TextSpan(text: '  向度数', style: labelStyle),
          TextSpan(text: '${facingDeg.toStringAsFixed(1)}°', style: valueStyle),
          const TextSpan(text: '  坐度数', style: labelStyle),
          TextSpan(text: '${sittingDeg.toStringAsFixed(1)}°', style: valueStyle),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 与指南针页一致：度数、八向、二十四山字均基于 **磁方位**（[_targetHeading] 五均滑窗 + [_compassRotationOffset]），
  /// 不使用盘面动画插值 [_heading]，也不再做廿四方位盘的显示 +90°。
  double _magneticHeadingForDisplay() {
    final raw = _isLocked
        ? (_lockedHeading + _compassRotationOffset)
        : (_targetHeading + _compassRotationOffset);
    return _normalizeDeg(raw);
  }

  /// 检查罗盘是否每转动 3 度需要触发一次声音和振动
  void _checkRotationHaptics(double oldHeading, double newHeading) {
    if (!_rotationSoundEnabled || _isLocked) return;

    // 归一化角度到 0-360
    final oldNormalized = (oldHeading % 360 + 360) % 360;
    final newNormalized = (newHeading % 360 + 360) % 360;

    // 计算每 3 度一个步进（共 120 个步进，对应 360 度）
    final oldStep = (oldNormalized / 3).floor();
    final newStep = (newNormalized / 3).floor();

    // 如果步进没有变化，直接返回
    if (newStep == _lastRotationStep) return;

    // 处理角度跨越 0/360 度的情况
    // 如果步进差值很大（> 60，即 > 180度），说明跨越了 0 度
    int stepDiff = newStep - oldStep;
    if (stepDiff.abs() > 60) {
      // 跨越了 0 度，需要调整步进差值
      if (stepDiff > 0) {
        stepDiff -= 120; // 逆时针跨越，实际是减少
      } else {
        stepDiff += 120; // 顺时针跨越，实际是增加
      }
    }

    // 如果步进发生变化（差值不为0），触发声音和振动
    if (stepDiff != 0) {
      _lastRotationStep = newStep;
      _playRotationHaptics();
    }
  }

  /// 播放一次声音和振动（用于罗盘转动反馈）
  void _playRotationHaptics() async {
    try {
      const channel = MethodChannel('haptic_feedback');

      // 同时播放声音和振动
      await channel.invokeMethod('playSound');
      await channel.invokeMethod('vibrate', {
        'duration': 50, // 短促的振动（毫秒）
        'amplitude': 128, // 中等强度
      });
    } catch (e) {
      // 如果平台通道失败，回退到 Flutter 内置方法
      try {
        SystemSound.play(SystemSoundType.click);
        HapticFeedback.lightImpact();
      } catch (_) {
        // 静默失败，不影响用户体验
      }
    }
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
    } catch (e) {
      print('初始化摄像头失败: $e');
    }
  }

  void _startSensors() {
    // 直接使用指南针传感器获取方向
    if (FlutterCompass.events != null) {
      _compassSubscription = FlutterCompass.events!.listen((event) {
        if (event.heading == null) return;

        // 指南针可能返回负数，需要转换为0-360度范围
        double heading = event.heading!;
        if (heading < 0) {
          heading = heading + 360;
        }
        heading = heading % 360;

        // 与 compass_page._startCompass 相同：5 点移动平均（处理跨 0°）
        _headingHistory.add(heading);
        if (_headingHistory.length > _headingHistorySize) {
          _headingHistory.removeAt(0);
        }
        double sum = 0.0;
        for (int i = 0; i < _headingHistory.length; i++) {
          double h = _headingHistory[i];
          if (i > 0) {
            double d = h - _headingHistory[0];
            if (d > 180) {
              h -= 360;
            } else if (d < -180) {
              h += 360;
            }
          }
          sum += h;
        }
        double smoothed = sum / _headingHistory.length;
        if (smoothed < 0) {
          smoothed += 360;
        } else if (smoothed >= 360) {
          smoothed -= 360;
        }

        // 指针始终跟踪磁北；盘面在锁定时才冻结
        _liveMagneticHeading = smoothed;
        if (!_isLocked) {
          _targetHeading = smoothed;
        }
        if (mounted) setState(() {});
      });
    }

    // 加速度计数据用于水平仪
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      // 计算俯仰角和横滚角
      double pitch = atan2(event.y, sqrt(event.x * event.x + event.z * event.z)) * (180 / pi);
      double roll = atan2(-event.x, event.z) * (180 / pi);

      // 更新目标值，平滑处理在动画控制器中完成
      _targetPitch = pitch;
      _targetRoll = roll;
    });
  }

  @override
  void dispose() {
    if (_smartTipKey != null || _isCameraEnabled) {
      widget.onSmartTipModeChanged?.call(false);
    }
    _zoomGuideTimer?.cancel();
    _dragGuideTimer?.cancel();
    _animationController.dispose();
    _compassSubscription?.cancel();
    _accelerometerSubscription.cancel();
    _cameraController?.dispose();
    _compassTransformController.dispose();
    _measureRemarkController.dispose();
    super.dispose();
  }

  Future<void> _toggleCamera() async {
    if (_isCameraEnabled) {
      // 关闭摄像头
      try {
        // 先更新UI状态，避免卡顿
        setState(() {
          _isCameraEnabled = false;
        });
        _notifyHomeBottomNavVisibility();

        // 异步释放摄像头资源，避免阻塞UI
        final controller = _cameraController;
        _cameraController = null;

        if (controller != null) {
          // 使用超时避免无限等待
          await controller.dispose().timeout(
            const Duration(seconds: 3),
            onTimeout: () {
              print('摄像头释放超时，强制释放');
            },
          ).catchError((error) {
            print('释放摄像头时出错: $error');
          });
        }
      } catch (e) {
        print('关闭摄像头失败: $e');
        // 即使出错也更新状态
        if (mounted) {
          setState(() {
            _isCameraEnabled = false;
            _cameraController = null;
          });
          _notifyHomeBottomNavVisibility();
        }
      }
    } else {
      // 请求摄像头权限
      final status = await Permission.camera.request();
      if (status.isGranted) {
        // 权限已授予，启动摄像头
        await _startCamera();
      } else {
        // 权限被拒绝，显示提示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('需要摄像头权限才能使用实景功能'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  Future<void> _startCamera() async {
    if (_cameras == null || _cameras!.isEmpty) {
      await _initializeCamera();
    }

    if (_cameras == null || _cameras!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('未找到可用的摄像头'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    try {
      // 使用后置摄像头
      final camera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      // 使用超时避免无限等待
      await controller.initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('摄像头初始化超时');
        },
      );

      if (mounted) {
        // 确保之前的控制器已释放
        await _cameraController?.dispose().catchError((e) {
          print('释放旧摄像头控制器时出错: $e');
        });

        setState(() {
          _cameraController = controller;
          _isCameraEnabled = true;
        });
        _notifyHomeBottomNavVisibility();
      } else {
        // 如果组件已卸载，释放控制器
        await controller.dispose();
      }
    } catch (e) {
      print('启动摄像头失败: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('启动摄像头失败: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 八向：北为 [337.5°,360°)∪[0°,22.5°]，东北 (22.5,67.5] … 每 45° 一格（与 (h+22.5)/45 等价）。
  String _getDirection(double heading) {
    double h = heading % 360;
    if (h < 0) h += 360;
    const directions = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
    final index = ((h + 22.5) / 45).floor() % 8;
    return directions[index];
  }

  String _getSittingDirection(double heading) => mountainAt(heading);

  String _getOppositeSittingDirection(double heading) =>
      oppositeMountainAt(heading);

  bool _isLongmenBajuBaseAsset(String assetPath) {
    final normalized = assetPath.replaceAll('\\', '/');
    if (!normalized.endsWith('/10-LongmenBaju.png')) return false;
    return normalized.contains('assets/black/') ||
        normalized.contains('assets/gold/') ||
        normalized.contains('assets/white/');
  }

  String? _getLongmenBajuOverlayAsset(double headingDeg) {
    final deg = (headingDeg % 360 + 360) % 360;

    if (deg >= 22 && deg < 67) return 'assets/longmenbaju/8-8.png';
    if (deg >= 67 && deg < 112) return 'assets/longmenbaju/3-3.png';
    if (deg >= 112 && deg < 157) return 'assets/longmenbaju/4-4.png';
    if (deg >= 157 && deg < 202) return 'assets/longmenbaju/9-9.png';
    if (deg >= 202 && deg < 247) return 'assets/longmenbaju/2-2.png';
    if (deg >= 247 && deg < 292) return 'assets/longmenbaju/7-7.png';
    if (deg >= 292 && deg < 337) return 'assets/longmenbaju/6-6.png';
    return 'assets/longmenbaju/1-1.png'; // 337~360 和 0~22
  }

  bool _isJiuXingFanguaBaseAsset(String assetPath) {
    final normalized = assetPath.replaceAll('\\', '/');
    if (!normalized.endsWith('/12-JiuxingFangua.png')) return false;
    return normalized.contains('assets/black/') ||
        normalized.contains('assets/gold/') ||
        normalized.contains('assets/white/');
  }

  // 九星翻卦 in/out 图层按“坐向组合”映射到 1~8。
  //
  // sittingFacing 形如：壬丙（坐壬向丙）、丙壬（坐丙向壬）等，二者必须区分。
  int? _getJiuXingFanguaInFrameBySittingFacing(String sittingFacing) {
    const s1 = {'壬丙', '寅申', '午子', '戌辰'};
    const s2 = {'子午', '癸丁', '辰戌', '申寅'};
    const s3 = {'丑未', '巳亥', '丁癸', '酉卯'};
    const s4 = {'艮坤', '丙壬'};
    const s5 = {'甲庚', '乾巽'};
    const s6 = {'卯酉', '未丑', '庚甲', '亥巳'};
    const s7 = {'乙辛', '坤艮'};
    const s8 = {'巽乾', '辛巳', '辛乙'};

    if (s1.contains(sittingFacing)) return 1;
    if (s2.contains(sittingFacing)) return 2;
    if (s3.contains(sittingFacing)) return 3;
    if (s4.contains(sittingFacing)) return 4;
    if (s5.contains(sittingFacing)) return 5;
    if (s6.contains(sittingFacing)) return 6;
    if (s7.contains(sittingFacing)) return 7;
    if (s8.contains(sittingFacing)) return 8;
    return null;
  }

  int? _getJiuXingFanguaOutFrameBySittingFacing(String sittingFacing) {
    const s1 = {'壬丙', '坤艮'};
    const s2 = {'子午', '辰戌', '丙壬', '申寅'};
    const s3 = {'癸丁', '卯酉', '未丑', '亥巳'};
    const s4 = {'丑未', '甲庚', '巳亥', '酉卯'};
    const s5 = {'艮坤', '辛乙'};
    const s6 = {'寅申', '午子', '丁癸', '戌辰'};
    const s7 = {'乙辛', '乾巽'};
    const s8 = {'巽乾', '庚甲'};

    if (s1.contains(sittingFacing)) return 1;
    if (s2.contains(sittingFacing)) return 2;
    if (s3.contains(sittingFacing)) return 3;
    if (s4.contains(sittingFacing)) return 4;
    if (s5.contains(sittingFacing)) return 5;
    if (s6.contains(sittingFacing)) return 6;
    if (s7.contains(sittingFacing)) return 7;
    if (s8.contains(sittingFacing)) return 8;
    return null;
  }

  // 获取对称角度的方向
  String _getOppositeDirection(double heading) {
    double oppositeHeading = (heading + 180) % 360;
    return _getDirection(oppositeHeading);
  }

  @override
  Widget build(BuildContext context) {
    // 盘面旋转仍用动画插值 [_heading]；顶部文字/度数与指南针页一致用 [_magneticHeadingForDisplay]
    final baseHeading = _isLocked ? _lockedHeading : _heading;
    final displayHeading = _magneticHeadingForDisplay();
    final direction = _getDirection(displayHeading);
    final sittingDirection = _getSittingDirection(displayHeading);
    final oppositeDirection = _getOppositeDirection(displayHeading);
    final oppositeSittingDirection = _getOppositeSittingDirection(displayHeading);
    final smartTipActive = _smartTipKey != null;
    final immersiveActive = smartTipActive || _isCameraEnabled;

    return Scaffold(
      backgroundColor: Colors.white, // 默认白色背景
      body: Stack(
        key: _compassBodyStackKey,
        children: [
          // 背景层：优先显示摄像头预览，其次显示背景图片，最后显示默认颜色
          if (_isCameraEnabled && _cameraController != null && _cameraController!.value.isInitialized)
            Positioned.fill(
              child: CameraPreview(_cameraController!),
            )
          else if (widget.backgroundImagePath != null &&
              widget.backgroundImagePath!.isNotEmpty)
            Positioned.fill(
              child: AppAssetImage(
                assetPath: widget.backgroundImagePath!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(color: Colors.white);
                },
              ),
            )
          else
            Container(color: Colors.white),
          // 主要内容
          SafeArea(
            bottom: !immersiveActive,
            child: Column(
              children: [
                _buildHeader(
                    sittingDirection, direction, displayHeading, _isLocked),
                Expanded(
                  child: smartTipActive
                      ? KeyedSubtree(
                          key: _smartTipCompassAreaKey,
                          child: _buildSmartTipCompassArea(baseHeading),
                        )
                      : Stack(
                          children: [
                            Transform.translate(
                              offset: const Offset(0, 24),
                              child: _buildCompass(baseHeading),
                            ),
                            if (_isCameraEnabled)
                              Positioned(
                                right: 16,
                                bottom: 90,
                                child: _buildOpacityButton(),
                              ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: _buildBottomControls(),
                            ),
                            if (_showRotationPanel)
                              Positioned(
                                right: 16,
                                top: 100,
                                child: _buildRotationPanel(),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          if (_smartTipKey == 'default')
            Positioned(
              left: 0,
              right: 0,
              top: _smartTipPanelTop(context),
              bottom: 0,
              child: KeyedSubtree(
                key: _smartTipPanelKey,
                child: _buildDefaultTipPanel(displayHeading: displayHeading),
              ),
            )
          else if (_smartTipKey != null)
            Positioned(
              left: 0,
              right: 0,
              top: _smartTipPanelTop(context),
              bottom: 0,
              child: KeyedSubtree(
                key: _smartTipPanelKey,
                child: _buildOtherTipPanel(
                  tipKey: _smartTipKey!,
                  displayHeading: displayHeading,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDefaultTipPanel({
    required double displayHeading,
  }) {
    final sittingDeg = _normalizeDeg(displayHeading + 180.0);
    final facing = _getSittingDirection(displayHeading);
    final sitting = _getOppositeSittingDirection(displayHeading);

    return _buildSmartTipSheetShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(
              children: [
                const Text(
                  '智能读盘',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildSmartTipHeadingSummaryRichText(displayHeading),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              color: Colors.white,
              child: !_defaultTipJsonLoaded
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  : _defaultTipJsonEntries.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                              '未加载到默认提示数据：请确认 pubspec 已包含 assets/default_tip_layers.json，执行 flutter clean 后完整重编译',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF888888),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                          itemBuilder: (context, index) {
                            final entry = _defaultTipJsonEntries[index];
                            final text = entry.resolve(
                                  sittingDeg,
                                  displayHeading,
                                  compassFacing: facing,
                                  compassSitting: sitting,
                                ) ??
                                '—';
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 5,
                                  child: Text(
                                    entry.displayName,
                                    style: const TextStyle(
                                      color: Color(0xFF555555),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 6,
                                  child: _buildDefaultTipDetailRichText(
                                    text,
                                    TextAlign.right,
                                  ),
                                ),
                              ],
                            );
                          },
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemCount: _defaultTipJsonEntries.length,
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtherTipPanel({
    required String tipKey,
    required double displayHeading,
  }) {
    final sittingDeg = _normalizeDeg(displayHeading + 180.0);
    final facing = _getSittingDirection(displayHeading);
    final sitting = _getOppositeSittingDirection(displayHeading);

    OtherTipJsonEntry? entry;
    for (final e in _otherTipEntries) {
      if (e.displayName == tipKey) {
        entry = e;
        break;
      }
    }

    final touDiLongZuo = _touDiPingFenSixtyDragonSitting(
      sittingDeg: sittingDeg,
      facingDialDeg: displayHeading,
    );

    final resolved = entry == null
        ? null
        : _resolveOtherTipForDetailPage(
            entry,
            sittingChar: sitting,
            facingChar: facing,
            sittingDeg: sittingDeg,
            facingDialDeg: displayHeading,
            touDiPingFenLongZuo: touDiLongZuo,
          );

    return _buildSmartTipSheetShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(
              children: [
                Text(
                  entry?.displayName ?? '智能读盘',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildSmartTipHeadingSummaryRichText(displayHeading),
                ),
              ],
            ),
          ),
          Expanded(
            child: !_otherTipJsonLoaded
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : entry == null
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            '未找到该提示数据',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF888888),
                              fontSize: 14,
                            ),
                          ),
                        ),
                      )
                    : resolved == null
                        ? SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.displayName,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: _kOtherTipDetailTitleColor,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SelectableText(
                                  _formatOtherTipJsonFallback(entry.root),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.5,
                                    color: _kOtherTipDetailBodyColor,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  resolved.title,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: _kOtherTipDetailTitleColor,
                                    height: 1.3,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SelectableText(
                                  resolved.body,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    height: 1.5,
                                    color: _kOtherTipDetailBodyColor,
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

  /// 智能读盘文案：「向:」「坐:」为黑色，其余保持金色。
  Widget _buildDefaultTipDetailRichText(
    String text,
    TextAlign align, {
    double fontSize = 14,
    double height = 1.35,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    final labelStyle = TextStyle(
      color: Colors.black,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      height: height,
    );
    final valueStyle = TextStyle(
      color: const Color(0xFF9C7A3F),
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      height: height,
    );
    final regex = RegExp(r'(向:|坐:)');
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in regex.allMatches(text)) {
      if (m.start > last) {
        spans.add(
            TextSpan(text: text.substring(last, m.start), style: valueStyle));
      }
      spans.add(TextSpan(text: m.group(0)!, style: labelStyle));
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: valueStyle));
    }
    if (spans.isEmpty) {
      return Text(
        text,
        textAlign: align,
        style: valueStyle,
        maxLines: maxLines,
        overflow: overflow ?? TextOverflow.clip,
      );
    }
    return Text.rich(
      TextSpan(children: spans),
      textAlign: align,
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }

  Widget _buildHeader(String sittingDirection, String direction, double heading, bool isLocked) {
    // 获取坐向的详细信息
    final oppositeSitting = _getOppositeSittingDirection(heading);
    final oppositeDirection = _getOppositeDirection(heading);
    final smartTipActive = _smartTipKey != null;
    final cameraActive = _isCameraEnabled;
    final showBackOnLeft = smartTipActive || cameraActive;

    return Container(
      key: _compassHeaderKey,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      color: Colors.transparent,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 指南针 / 返回 + 2. 锁定（左侧成组，固定宽度不占中间弹性空间）
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              showBackOnLeft
                  ? IconButton(
                      onPressed: smartTipActive
                          ? _exitSmartTipMode
                          : _toggleCamera,
                      icon: Icon(
                        Icons.arrow_back_ios_new,
                        size: 18,
                        color: cameraActive && !smartTipActive
                            ? Colors.white
                            : const Color(0xFFC69C52),
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      tooltip: '返回',
                    )
                  : GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const CompassPage(),
                          ),
                        );
                      },
                      child: const HomeToolbarIcon(
                        assetPath: 'assets/home/zhinanzhen.png',
                        size: 36,
                        fallbackIcon: Icons.explore,
                        fallbackIconSize: 24,
                      ),
                    ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  if (_isLocked) {
                    setState(() {
                      _isLocked = false;
                      _showRotationPanel = false;
                      _compassRotationOffset = 0.0;
                    });
                  } else {
                    setState(() {
                      _isLocked = true;
                      _lockedHeading = _heading;
                      _compassRotationOffset = 0.0;
                      _showRotationPanel = true;
                    });
                    print(
                        '显示调整面板，锁定角度: ${_lockedHeading.toStringAsFixed(1)}°');
                  }
                },
                child: SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    isLocked ? Icons.lock : Icons.lock_open,
                    color: Colors.grey,
                    size: 28,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(width: 4),

          // 3. 坐向信息
          Flexible(
            flex: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '坐:$oppositeDirection',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 9,
                    ),
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '向:$direction',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 9,
                    ),
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 4),

          // 4. 角度显示和智能读盘
          Flexible(
            flex: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${heading.toStringAsFixed(1)}°',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      softWrap: false,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                GestureDetector(
                  onTap: _showSmartTipsDrawer,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '智能读盘',
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          softWrap: false,
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 8,
                          color: Colors.grey[600],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 4),

          // 5. 坤宅 / 山向信息
          Flexible(
            flex: 2,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    formatBazhaiZhaiLabel(heading),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
                Text(
                  formatMountainFacing(heading),
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 10,
                    height: 1.25,
                  ),
                  softWrap: true,
                ),
              ],
            ),
          ),

          const SizedBox(width: 4),

          // 6. 「保存 测量」按钮（未锁定时点击提示先锁定）
          GestureDetector(
            onTap: () {
              if (isLocked) {
                _showMeasurementRecordSheet();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请先点击锁定后，保存')),
                );
              }
            },
            child: const HomeToolbarIcon(
              assetPath: 'assets/home/save.png',
              size: 36,
              fallbackIcon: Icons.save_alt,
              fallbackIconSize: 22,
            ),
          ),

          const SizedBox(width: 4),

          // 7. 菜单按钮（智能读盘模式下为「切换提示」）
          Flexible(
            flex: 2,
            child: smartTipActive
                ? GestureDetector(
                    onTap: _showSmartTipsDrawer,
                    child: Container(
                      width: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E8),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: const Color(0xFFC69C52),
                          width: 1,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 5),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '切换',
                            style: TextStyle(
                              color: Color(0xFFC69C52),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              height: 1.1,
                            ),
                            maxLines: 1,
                            softWrap: false,
                          ),
                          Text(
                            '提示',
                            style: TextStyle(
                              color: Color(0xFFC69C52),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              height: 1.1,
                            ),
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ],
                      ),
                    ),
                  )
                : PopupMenuButton<String>(
              offset: const Offset(0, 5), // 从按钮下方弹出
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 8,
              color: Colors.white,
              onSelected: (String value) async {
                if (value == '样式') {
                  // 点击样式后跳转到选择罗盘页面
                  if (widget.onMenuPressed != null) {
                    widget.onMenuPressed!();
                  }
                } else if (value == '设置') {
                  // 从右侧弹出设置抽屉
                  _showSettingsDrawer();
                } else if (value == '实景罗盘') {
                  await _toggleCamera();
                } else if (value == '地图罗盘') {
                  if (!context.mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const MapCompassPage(),
                    ),
                  );
                } else if (value == '说明书') {
                  // 指引说明书：依次展示放大/拖动 GIF
                  _startGuideSequence();
                } else if (value == '测量记录') {
                  _showMeasureRecordListSheet();
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: '设置',
                  child: Row(
                    children: [
                      Icon(Icons.settings, size: 20, color: Colors.grey[700]),
                      const SizedBox(width: 12),
                      const Text(
                        '设置',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: '样式',
                  child: Row(
                    children: [
                      Icon(Icons.palette, size: 20, color: Colors.grey[700]),
                      const SizedBox(width: 12),
                      const Text(
                        '样式',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: '说明书',
                  child: Row(
                    children: [
                      Icon(Icons.menu_book, size: 20, color: Colors.grey[700]),
                      const SizedBox(width: 12),
                      const Text(
                        '说明书',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: '测量记录',
                  child: Row(
                    children: [
                      Icon(Icons.history, size: 20, color: Colors.grey[700]),
                      const SizedBox(width: 12),
                      const Text(
                        '测量记录',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: '实景罗盘',
                  child: Row(
                    children: [
                      Icon(
                        _isCameraEnabled
                            ? Icons.camera_alt
                            : Icons.camera_alt_outlined,
                        size: 20,
                        color: Colors.grey[700],
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _isCameraEnabled ? '关闭实景罗盘' : '实景罗盘',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem<String>(
                  value: '地图罗盘',
                  child: Row(
                    children: [
                      Icon(Icons.map_outlined, size: 20, color: Colors.grey[700]),
                      const SizedBox(width: 12),
                      const Text(
                        '地图罗盘',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              child: const HomeToolbarIcon(
                assetPath: 'assets/home/menu.png',
                size: 36,
                fallbackIcon: Icons.menu,
                fallbackIconSize: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _startGuideSequence() {
    // 重置状态
    _zoomGuideTimer?.cancel();
    _dragGuideTimer?.cancel();
    setState(() {
      _showZoomGuide = true;
      _showDragGuide = false;
    });

    // 8 秒后自动隐藏放大指引并显示拖动指引（如果用户还没放大过）
    _zoomGuideTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      if (_showZoomGuide) {
        setState(() {
          _showZoomGuide = false;
          _showDragGuide = true;
        });
        _startDragGuideTimer();
      }
    });
  }

  void _startDragGuideTimer() {
    _dragGuideTimer?.cancel();
    _dragGuideTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() {
        _showDragGuide = false;
      });
    });
  }

  Future<void> _slideInSideDrawer({
    required String barrierLabel,
    required Widget Function(BuildContext ctx, StateSetter setDialogState) child,
    VoidCallback? onDismissed,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: barrierLabel,
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (ctx, anim1, anim2) {
        final width = MediaQuery.of(ctx).size.width * 0.76;
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: const Color(0xFFF2F2F2),
            child: SizedBox(
              width: width,
              height: double.infinity,
              child: SafeArea(
                child: StatefulBuilder(
                  builder: (context, setDialogState) {
                    return child(context, setDialogState);
                  },
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        ));
        return SlideTransition(
          position: offsetAnimation,
          child: child,
        );
      },
    ).whenComplete(() => onDismissed?.call());
  }

  /// 菜单「设置」：罗盘相关设置（与智能提示分开）
  void _showSettingsDrawer() {
    _slideInSideDrawer(
      barrierLabel: 'Settings',
      child: (context, setDialogState) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                '设置',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF444444),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                children: [
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _showCalibrationDialog();
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '校准',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[800],
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              color: Colors.grey[600], size: 22),
                        ],
                      ),
                    ),
                  ),
                  _buildSettingsSwitchRow(
                    label: '转动声音振动',
                    value: _rotationSoundEnabled,
                    onChanged: (v) {
                      setState(() => _rotationSoundEnabled = v);
                      setDialogState(() {});
                    },
                  ),
                  _buildSettingsSwitchRow(
                    label: '天心十道',
                    value: _tianXinShiDaoEnabled,
                    onChanged: (v) {
                      setState(() => _tianXinShiDaoEnabled = v);
                      setDialogState(() {});
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// 点击「智能读盘」：智能提示类型抽屉
  void _showSmartTipsDrawer() {
    _slideInSideDrawer(
      barrierLabel: 'SmartTips',
      onDismissed: () => _smartTipsDrawerStateSetter = null,
      child: (context, setDialogState) {
        _smartTipsDrawerStateSetter = setDialogState;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                '智能提示',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF444444),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                children: [
                  _buildSettingsSwitchRow(
                    label: '默认提示',
                    value: _smartTipKey == 'default',
                    onChanged: (v) {
                      setState(() => _applySmartTipSwitch('default', v));
                      setDialogState(() {});
                    },
                  ),
                  if (!_otherTipJsonLoaded)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    ..._otherTipEntries.map(
                      (e) => _buildSettingsSwitchRow(
                        label: e.displayName,
                        value: _smartTipKey == e.displayName,
                        onChanged: (v) {
                          setState(
                              () => _applySmartTipSwitch(e.displayName, v));
                          setDialogState(() {});
                        },
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
    // 首帧后再拉取：先让 StatefulBuilder 挂上 [_smartTipsDrawerStateSetter]，避免加载过快时无法刷新弹层
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadOtherTipJsonEntries());
    });
  }

  /// 设置抽屉中的单行动作按钮（如：校准）
  Widget _buildSettingsActionRow({
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                color: Colors.white,
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  /// 校准弹窗（包含 assets/jiaozhun.gif 动画）
  void _showCalibrationDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
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
                  '校准',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '如指针方向不稳定或偏差较大，请按如下方式校准：\n'
                  '1. 将手机远离金属物体、磁铁及大功率电器；\n'
                  '2. 手持手机按“8”字形缓慢摆动数次；\n'
                  '3. 再次进入罗盘观察是否恢复正常。',
                  style: TextStyle(fontSize: 14, height: 1.5),
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AppAssetImage(
                    assetPath: 'assets/jiaozhun.gif',
                    height: 220,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 20),
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
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text(
                      '确定',
                      style: TextStyle(fontSize: 16, color: Colors.white),
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

  /// 设置抽屉中的单行开关样式
  Widget _buildSettingsSwitchRow({
    required String label,
    required bool value,
    bool showPaidTag = false,
    required ValueChanged<bool> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF666666),
                  ),
                ),
                if (showPaidTag) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC89D4E),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '付费',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            Transform.scale(
              scale: 0.92,
              child: Switch(
                value: value,
                onChanged: onChanged,
                activeColor: Colors.white,
                activeTrackColor: const Color(0xFFC89D4E),
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: const Color(0xFFE2E2E2),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalLevel(double angle) {
    // 将角度转换为气泡位置（-1 到 1）
    double normalizedAngle = angle.clamp(-30.0, 30.0) / 30.0;
    double bubblePosition = normalizedAngle;

    return Container(
      width: 30,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.3),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.amber, width: 1.5),
      ),
      child: Stack(
        children: [
          // 中心线（垂直）
          Center(
            child: Container(
              width: 1.5,
              height: double.infinity,
              color: Colors.amber.withOpacity(0.5),
            ),
          ),
          // 气泡
          Positioned(
            left: 3,
            right: 3,
            top: 50 + (bubblePosition * 50).clamp(-50.0, 50.0),
            child: Container(
              width: 24,
              height: 16,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.amber, width: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalLevel(double angle) {
    // 将角度转换为气泡位置（-1 到 1）
    double normalizedAngle = angle.clamp(-30.0, 30.0) / 30.0;
    double bubblePosition = normalizedAngle;

    return Container(
      width: 120,
      height: 30,
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.3),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.amber, width: 1.5),
      ),
      child: Stack(
        children: [
          // 中心线（水平）
          Center(
            child: Container(
              width: double.infinity,
              height: 1.5,
              color: Colors.amber.withOpacity(0.5),
            ),
          ),
          // 气泡
          Positioned(
            top: 3,
            bottom: 3,
            left: 50 + (bubblePosition * 50).clamp(-50.0, 50.0),
            child: Container(
              width: 16,
              height: 24,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.amber, width: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpacityButton() {
    return GestureDetector(
      onTap: _showCompassOpacityDialog,
      child: Container(
        width: 56,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.35), width: 1),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.opacity,
              color: Colors.white,
              size: 22,
            ),
            SizedBox(height: 4),
            Text(
              '透明度',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCompassOpacityDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final original = _compassOpacity;
        double temp = _compassOpacity;
        return AlertDialog(
          title: const Text('实景罗盘设置'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Slider(
                    value: temp,
                    min: 0.2,
                    max: 1.0,
                    divisions: 8,
                    label: '${(temp * 100).round()}%',
                    onChanged: (v) {
                      setDialogState(() => temp = v);
                      // 实时生效
                      setState(() => _compassOpacity = v);
                    },
                  ),
                  Text('透明度：${(temp * 100).round()}%'),
                  const SizedBox(height: 12),
                  // 白线条 / 黑线条 单选
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Radio<bool>(
                            value: false,
                            groupValue: _useBlackLine,
                            onChanged: (value) {
                              if (value == null) return;
                              setDialogState(() {});
                              setState(() {
                                _useBlackLine = value;
                              });
                            },
                          ),
                          const Text('白线条'),
                        ],
                      ),
                      const SizedBox(width: 16),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Radio<bool>(
                            value: true,
                            groupValue: _useBlackLine,
                            onChanged: (value) {
                              if (value == null) return;
                              setDialogState(() {});
                              setState(() {
                                _useBlackLine = value;
                              });
                            },
                          ),
                          const Text('黑线条'),
                        ],
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                // 取消时恢复原值
                setState(() => _compassOpacity = original);
                Navigator.of(ctx).pop();
              },
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  /// 中心圆盘水平仪：在罗盘中心空白圆盘中显示 gs.png，并根据 pitch/roll 移动气泡
  Widget _buildCenterLevelDisc({required double pitch, required double roll}) {
    // 将角度限制在 [-30, 30]，再归一化到 [-1, 1]
    final nx = roll.clamp(-30.0, 30.0) / 30.0; // 左右倾斜 -> X
    final ny = (-pitch).clamp(-30.0, 30.0) / 30.0; // 前后倾斜 -> Y（取反更符合直觉）

    const double size = 110; // 中心圆盘大小
    const double bubbleSize = 16;
    const double padding = 10;
    final double radius = size / 2 - bubbleSize / 2 - padding;
    final double dx = (nx * radius).clamp(-radius, radius);
    final double dy = (ny * radius).clamp(-radius, radius);

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 底盘：不使用图片，改为纯绘制的圆盘（刻度+十字线）
            CustomPaint(
              painter: _CenterLevelDiscPainter(),
            ),
            Positioned(
              left: size / 2 - bubbleSize / 2 + dx,
              top: size / 2 - bubbleSize / 2 + dy,
              child: Container(
                width: bubbleSize,
                height: bubbleSize,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: Colors.black.withOpacity(0.6), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.25),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompass(double heading) {
    // 计算最终的旋转角度：基础角度 + 用户调整的偏移角度
    final finalHeading = (heading + _compassRotationOffset) % 360;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 让罗盘尽可能占满当前可用区域（取最大正方形），避免只在中间小块显示
        final double size = min(constraints.maxWidth, constraints.maxHeight);

        return SizedBox.expand(
          child: InteractiveViewer(
            transformationController: _compassTransformController,
            minScale: 1.0,
            maxScale: 3.0,
            panEnabled: true,
            scaleEnabled: true,
            // 给足边界，避免放大后被“卡边”
            boundaryMargin: const EdgeInsets.all(200),
            onInteractionStart: (_) {
              // 用户完成放大操作后，隐藏放大指引并开始拖动指引
              if (_showZoomGuide) {
                setState(() {
                  _zoomGuideTimer?.cancel();
                  _dragGuideTimer?.cancel();
                  _showZoomGuide = false;
                  _showDragGuide = true;
                  _startDragGuideTimer();
                });
              }
            },
            onInteractionEnd: (_) {
              // 接近原始大小时自动回弹到居中
              final currentScale =
                  _compassTransformController.value.getMaxScaleOnAxis();
              if (currentScale <= 1.02) {
                _compassTransformController.value = Matrix4.identity();
              }
            },
            child: Center(
              child: SizedBox(
                width: size,
                height: size,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 罗盘主体（受透明度控制）
                    Opacity(
                      opacity: _compassOpacity,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // 罗盘背景图片：
                          // - 普通首页罗盘：使用 assets/white 或 assets/black 下的原始盘面图
                          // - 实景罗盘：只使用 touming-* 下的透明线条图，不再叠加原始盘面
                          Builder(
                            builder: (context) {
                              final fileName =
                                  widget.compassImagePath.split('/').last;
                              final String bgPath;
                              if (_isCameraEnabled) {
                                bgPath = _useBlackLine
                                    ? 'assets/touming-black/$fileName'
                                    : 'assets/touming-white/$fileName';
                              } else {
                                bgPath = widget.compassImagePath;
                              }
                              final overlayPath =
                                  _isLongmenBajuBaseAsset(bgPath)
                                      ? _getLongmenBajuOverlayAsset(finalHeading)
                                      : null;
                              final int? jiuXingFrameIn;
                              final int? jiuXingFrameOut;
                              if (_isJiuXingFanguaBaseAsset(bgPath)) {
                                final sitting =
                                    _getOppositeSittingDirection(finalHeading);
                                final facing = _getSittingDirection(finalHeading);
                                final sittingFacing = '$sitting$facing';
                                jiuXingFrameIn =
                                    _getJiuXingFanguaInFrameBySittingFacing(
                                        sittingFacing);
                                jiuXingFrameOut =
                                    _getJiuXingFanguaOutFrameBySittingFacing(
                                        sittingFacing);
                              } else {
                                jiuXingFrameIn = null;
                                jiuXingFrameOut = null;
                              }

                              return Transform.rotate(
                                angle: (-finalHeading * pi / 180 + pi / 2) +
                                    extraInitialRotationForAsset(bgPath),
                                child: Container(
                                  width: size,
                                  height: size,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 20,
                                        spreadRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: ClipOval(
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        AppAssetImage(
                                      assetPath: bgPath,
                                      fit: BoxFit.cover,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        return Container(
                                          color: Colors.amber,
                                          child: const Center(
                                            child: Icon(
                                              Icons.error,
                                              color: Colors.white,
                                              size: 50,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                        if (overlayPath != null)
                                          Center(
                                            child: Transform.scale(
                                              scale: _longmenBajuOverlayScale,
                                              child: ColorFiltered(
                                                colorFilter: const ColorFilter.mode(
                                                  Colors.black,
                                                  BlendMode.srcIn,
                                                ),
                                                child: AppAssetImage(
                                                  assetPath: overlayPath,
                                                  width: size,
                                                  height: size,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            ),
                                          ),
                                        if (jiuXingFrameOut != null) ...[
                                          ColorFiltered(
                                            colorFilter: const ColorFilter.mode(
                                              Colors.black,
                                              BlendMode.srcIn,
                                            ),
                                            child: AppAssetImage(
                                              assetPath: 'assets/jiuxingfangua/out/$jiuXingFrameOut.png',
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ],
                                        if (jiuXingFrameIn != null) ...[
                                          ColorFiltered(
                                            colorFilter: const ColorFilter.mode(
                                              Colors.black,
                                              BlendMode.srcIn,
                                            ),
                                            child: AppAssetImage(
                                              assetPath: 'assets/jiuxingfangua/in/$jiuXingFrameIn.png',
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),

                          // 天心十道：贯穿整个罗盘直径的红色十字线
                          if (_tianXinShiDaoEnabled)
                            IgnorePointer(
                              child: CustomPaint(
                                size: Size(size, size),
                                painter: CrosshairPainter(),
                              ),
                            ),

                          // 中心圆盘：水平仪底图 + 气泡
                          _buildCenterLevelDisc(pitch: _pitch, roll: _roll),
                        ],
                      ),
                    ),

                    // 罗盘指针图：置顶显示，不随盘面旋转，始终指向磁北（0°）
                    IgnorePointer(
                      child: Transform.rotate(
                        angle: luopanNeedleRotationRadians(_liveMagneticHeading),
                        child: AppAssetImage(
                          assetPath: 'assets/luopanzhizhen.png',
                          width: size * 0.30,
                          height: size * 0.30,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),

                    // 新手指引 GIF 覆盖层（需要盖在最上层）
                    if (_showZoomGuide || _showDragGuide)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            alignment: Alignment.center,
                            color: Colors.black.withOpacity(0.15),
                            child: AppAssetImage(
                              assetPath: _showZoomGuide
                                  ? 'assets/shuomingshu/fangda.gif'
                                  : 'assets/shuomingshu/tuodong.gif',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // 实景罗盘透明线条底图已与 assets/white / assets/black 同名，
  // 因此不再需要按盘型映射 key，直接按文件名从 assets/touming-* 加载。

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 左侧
          const SizedBox.shrink(),

          // 中间
          Column(
            children: [
              // 向下黄色箭头：按需求隐藏（如需恢复，取消注释即可）
              // const Icon(Icons.arrow_drop_down, color: Colors.amber, size: 30),
              const SizedBox.shrink(),
              // 坐向度数显示：按需求隐藏（如需恢复，取消注释即可）
              // Builder(
              //   builder: (context) {
              //     // 使用与顶部相同的displayHeading计算方式
              //     final baseHeading = _isLocked ? _lockedHeading : _heading;
              //     final displayHeading =
              //         (baseHeading + _compassRotationOffset) % 360;
              //     final oppositeSitting =
              //         _getOppositeSittingDirection(displayHeading);
              //     final oppositeDir = _getOppositeDirection(displayHeading);
              //     final oppositeHeading = (displayHeading + 180) % 360;
              //     return Text(
              //       '$oppositeSitting山 $oppositeDir${oppositeHeading.toStringAsFixed(1)}°',
              //       style: const TextStyle(color: Colors.white, fontSize: 12),
              //     );
              //   },
              // ),
              const SizedBox.shrink(),
            ],
          ),

          // 右侧
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 海拔按钮：按需求隐藏（如需恢复，取消注释即可）
              // GestureDetector(
              //   onTap: () {
              //     _showAltitudeBottomSheet();
              //   },
              //   child: const Text(
              //     '海拔 >>',
              //     style: TextStyle(color: Colors.white, fontSize: 12),
              //   ),
              // ),
              const SizedBox.shrink(),
            ],
          ),
        ],
      ),
    );
  }

  // 获取位置信息
  Future<void> _getLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _isLoadingAltitude = true;
    });

    try {
      // 检查位置权限
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请启用位置服务')),
          );
        }
        setState(() {
          _isLoadingLocation = false;
        });
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('需要位置权限')),
            );
          }
          setState(() {
            _isLoadingLocation = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('位置权限被永久拒绝')),
          );
        }
        setState(() {
          _isLoadingLocation = false;
        });
        return;
      }

      // 获取当前位置
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _altitude = position.altitude;
          _isLoadingLocation = false;
          _isLoadingAltitude = false;
        });
        print('位置获取成功: 纬度=$_latitude, 经度=$_longitude, 海拔=$_altitude');

        // 通知抽屉更新
        _updateSheet();

        // 获取地址信息
        _getAddressFromCoordinates(position.latitude, position.longitude);
      }
    } catch (e) {
      print('获取位置失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
          _isLoadingAltitude = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取位置失败: $e')),
        );
      }
    }
  }

  // 获取气压数据（使用模拟数据，因为sensors_plus不支持气压传感器）
  void _startBarometer() {
    // sensors_plus包不直接支持气压传感器
    // 这里使用标准海平面气压作为参考值
    setState(() {
      _seaLevelPressure = 1025.0; // 标准海平面气压（hPa）
      // 如果没有气压传感器，可以尝试从GPS海拔反推气压
      // 或者使用天气API获取当前气压
      _pressure = null; // 需要气压传感器才能获取
    });
  }

  // 停止气压传感器
  void _stopBarometer() {
    // 无需操作，因为没有实际的传感器订阅
  }

  // 显示海拔信息底部抽屉
  void _showAltitudeBottomSheet() {
    // 开始获取位置和气压
    _getLocation();
    _startBarometer();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        // 使用StreamBuilder来实时监听状态变化
        return StreamBuilder<void>(
          stream: Stream.periodic(const Duration(milliseconds: 500)),
          builder: (context, snapshot) {
            return Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey, width: 0.5),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '经纬度与海拔信息',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            // 内容区域
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 经纬度
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _latitude != null
                              ? '北纬${_formatCoordinate(_latitude!, true)}'
                              : '获取中...',
                          style: const TextStyle(fontSize: 16),
                        ),
                        Text(
                          _longitude != null
                              ? '东经${_formatCoordinate(_longitude!, false)}'
                              : '获取中...',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                    // 添加刷新按钮用于手动刷新
                    if (_isLoadingLocation)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '正在获取位置信息...',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 20),
                    // 大气压
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _seaLevelPressure != null
                              ? '海平面大气压:${_seaLevelPressure!.toStringAsFixed(0)}hPa'
                              : '海平面大气压:获取中...',
                          style: const TextStyle(fontSize: 16),
                        ),
                        Text(
                          _pressure != null
                              ? '地面:${_pressure!.toStringAsFixed(0)}hPa'
                              : '地面:获取中...',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // 海拔
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _pressure != null
                              ? '我的海拔:${_calculateAltitude().toStringAsFixed(0)}米'
                              : '我的海拔:需气压传感器',
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _isLoadingAltitude
                              ? '地面海拔:获取中...'
                              : (_altitude != null
                                  ? '地面海拔:${_altitude!.toStringAsFixed(0)}米'
                                  : '地面海拔:获取中...'),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // 免责声明
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        '(注:因设备气压传感器的差异和环境的影响,以及大气压数据的原因,海拔的测量误差可能在±8米内)',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
            );
          },
        );
      },
    );
  }

  // 格式化坐标（度分秒）
  String _formatCoordinate(double coordinate, bool isLatitude) {
    int degrees = coordinate.abs().floor();
    double minutesDecimal = (coordinate.abs() - degrees) * 60;
    int minutes = minutesDecimal.floor();
    double seconds = (minutesDecimal - minutes) * 60;

    String direction = isLatitude
        ? (coordinate >= 0 ? '北纬' : '南纬')
        : (coordinate >= 0 ? '东经' : '西经');

    return '$degrees°$minutes\'${seconds.toStringAsFixed(0)}"';
  }

  // 根据气压计算海拔（使用气压高度公式）
  double _calculateAltitude() {
    if (_pressure == null || _seaLevelPressure == null) {
      return 0.0;
    }

    // 使用标准大气压高度公式
    // h = 44330 * (1 - (P/P0)^0.1903)
    // 其中 P0 是海平面气压，P 是当前气压
    double altitude = 44330 * (1 - pow(_pressure! / _seaLevelPressure!, 0.1903).toDouble());
    return altitude;
  }

  // 根据坐标获取地址（返回拼接后的地址字符串）
  Future<String?> _getAddressFromCoordinates(double latitude, double longitude) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String address = '';
        if (place.country != null && place.country!.isNotEmpty) {
          address += place.country!;
        }
        if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
          address += place.administrativeArea!;
        }
        if (place.locality != null && place.locality!.isNotEmpty) {
          address += place.locality!;
        }
        if (place.subLocality != null && place.subLocality!.isNotEmpty) {
          address += place.subLocality!;
        }
        if (place.street != null && place.street!.isNotEmpty) {
          address += place.street!;
        }
        if (place.subThoroughfare != null && place.subThoroughfare!.isNotEmpty) {
          address += place.subThoroughfare!;
        }

        if (mounted) {
          setState(() {
            _address = address.isNotEmpty ? address : '获取中...';
          });
          // 通知抽屉更新
          _updateSheet();
        }
        return address.isNotEmpty ? address : null;
      }
    } catch (e) {
      print('获取地址失败: $e');
      if (mounted) {
        setState(() {
          _address = '获取失败';
        });
        // 通知抽屉更新
        _updateSheet();
      }
      return null;
    }
    return null;
  }

  // 获取罗盘名称（从路径解析）
  String _getCompassName() {
    String path = widget.compassImagePath;
    // 从路径中提取文件名，例如：assets/gold/0-SimplePlate-BaguaTwentyFour.png
    if (path.contains('0-SimplePlate-BaguaTwentyFour')) {
      return '简易盘·八卦廿四山';
    } else if (path.contains('1-SimplePlate-TwentyFourDirection')) {
      return '简易盘·廿四方位';
    } else if (path.contains('2-BeginnerPlate')) {
      return '入门盘';
    } else if (path.contains('3-Beginner-XuankongPlate')) {
      return '入门盘·玄空';
    } else if (path.contains('4-SanhePlate-KaixiSuDu')) {
      return '三合盘·开禧宿度';
    } else if (path.contains('5-SanyuanPlate-ShixianSuDu')) {
      return '三元盘·时宪宿度';
    } else if (path.contains('6-XuankongFeixing-EightNineYun')) {
      return '玄空飞星·八九运';
    } else if (path.contains('7-TwentyEightLayerComprehensive')) {
      return '二十八层综合盘';
    } else if (path.contains('8-JinsuoYuguanPlate')) {
      return '金锁玉关盘';
    } else if (path.contains('9-XiangshangTwelveChangSheng')) {
      return '向上十二长生';
    } else if (path.contains('10-LongmenBaju')) {
      return '龙门八局';
    } else if (path.contains('11-BazhaiFengshui')) {
      return '八宅风水';
    } else if (path.contains('12-JiuxingFangua')) {
      return '九星翻卦';
    }
    return '未知罗盘';
  }

  // 获取农历时间（简化版本，实际应该使用农历库）
  String _getLunarDate() {
    final now = DateTime.now();
    // 这里使用简化的农历显示，实际应该使用专业的农历库
    // 格式：2025-12-27 02:06 农历冬月初八丁丑时
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} 农历冬月初八丁丑时';
  }

  String _getSittingDetail(double heading) => formatSittingDetail(heading);

  String _getFacingDetail(double heading) => formatFacingDetail(heading);

  // 更新抽屉内容
  void _updateSheet() {
    _sheetStateSetter?.call(() {});
  }

  // 显示测量记录抽屉
  void _showMeasurementRecordSheet() {
    // 确保有位置信息
    if (_latitude == null || _longitude == null) {
      _getLocation();
    }

    // 如果没有地址，尝试获取
    if (_address == null && _latitude != null && _longitude != null) {
      _getAddressFromCoordinates(_latitude!, _longitude!);
    }

    final displayHeading = _magneticHeadingForDisplay();
    final oppositeHeading = _normalizeDeg(displayHeading + 180);
    final sittingDirection = _getSittingDirection(displayHeading);
    final oppositeSitting = _getOppositeSittingDirection(displayHeading);
    final direction = _getDirection(displayHeading);
    final oppositeDirection = _getOppositeDirection(displayHeading);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          // 保存状态更新函数
          _sheetStateSetter = setModalState;

          return Container(
            height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey, width: 0.5),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Text(
                    '测量记录',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                    ElevatedButton(
                    onPressed: _isSavingMeasureRecord
                        ? null
                        : () async {
                            await _saveMeasureRecord();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: _isSavingMeasureRecord
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('保存'),
                  ),
                ],
              ),
            ),
            // 内容区域
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 坐向信息卡片
                    _buildInfoCard('坐', '$oppositeDirection${oppositeHeading.toStringAsFixed(1)}°'),
                    _buildInfoCard('向', '$direction${displayHeading.toStringAsFixed(1)}°'),
                    _buildInfoCard('坐', _getSittingDetail(displayHeading)),
                    _buildInfoCard('向', _getFacingDetail(displayHeading)),

                    const SizedBox(height: 16),

                    // 测量罗盘
                    _buildInfoCard('测量罗盘:', _getCompassName()),

                    const SizedBox(height: 16),

                    // 测量时间
                    _buildInfoCard('测量时间:', _getLunarDate()),

                    const SizedBox(height: 16),

                    // 测量地点
                    _buildInfoCard('测量地点:', _address ?? '获取中...'),

                    const SizedBox(height: 16),

                    // 经纬度
                    _buildInfoCard(
                      '经纬度:',
                      _latitude != null && _longitude != null
                          ? '东经${_formatCoordinate(_longitude!, false)} 北纬${_formatCoordinate(_latitude!, true)}'
                          : '获取中...',
                    ),

                    // 海拔
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '海拔:',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _pressure != null
                                ? '测量海拔: ${_calculateAltitude().toStringAsFixed(0)}米'
                                : '测量海拔: 需气压传感器',
                            style: const TextStyle(fontSize: 16),
                          ),
                          if (_altitude != null)
                            Text(
                              '地面海拔: ${_altitude!.toStringAsFixed(0)}米',
                              style: const TextStyle(fontSize: 16),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 输入框
                    TextField(
                      controller: _measureRemarkController,
                      decoration: const InputDecoration(
                        hintText: '输入分析评语、备注...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 5,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
          );
        },
      ),
    ).then((_) {
      // 抽屉关闭后清理状态更新函数
      _sheetStateSetter = null;
    });
  }

  void _showMeasureRecordListSheet() {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (ctx) => MeasureRecordListPage(baseUrl: _baseUrl),
      ),
    );
  }

  void _setSavingMeasureRecord(bool saving) {
    if (!mounted) return;
    setState(() => _isSavingMeasureRecord = saving);
    _sheetStateSetter?.call(() {});
  }

  Future<void> _showMeasureRecordAlert(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveMeasureRecord() async {
    final user = AuthService.currentUser.value;
    if (!AuthService.isLoggedIn || user == null || user.userId <= 0) {
      await _showMeasureRecordAlert('提示', '未登录，无法保存测量记录');
      return;
    }

    _setSavingMeasureRecord(true);
    try {
      // 确保经纬度已获取（否则保存会是空）
      if (_latitude == null || _longitude == null) {
        await _getLocation();
      }
      final lat = _latitude;
      final lon = _longitude;
      if (lat == null || lon == null) {
        await _showMeasureRecordAlert(
          '提示',
          '无法获取经纬度，请开启定位权限后重试',
        );
        return;
      }

      // 确保测量地点已获取（否则保存会是空/获取中）
      final currentAddr = (_address ?? '').trim();
      if (currentAddr.isEmpty ||
          currentAddr == '获取中...' ||
          currentAddr == '获取失败') {
        await _getAddressFromCoordinates(lat, lon);
      }
      final addrToSave = ((_address ?? '').trim().isEmpty ||
              (_address ?? '').trim() == '获取中...' ||
              (_address ?? '').trim() == '获取失败')
          ? ''
          : (_address ?? '').trim();

      final displayHeading = _magneticHeadingForDisplay();
      final oppositeHeading = _normalizeDeg(displayHeading + 180);
      final direction = _getDirection(displayHeading);
      final oppositeDirection = _getOppositeDirection(displayHeading);

      final compassImageUrl = storageAssetReference(widget.compassImagePath);
      final body = <String, dynamic>{
        'userId': user.userId,
        'compassName': _getCompassName(),
        'compassAsset': compassImageUrl,
        'compassImage': compassImageUrl,
        'sittingDegree': double.parse(oppositeHeading.toStringAsFixed(1)),
        'facingDegree': double.parse(displayHeading.toStringAsFixed(1)),
        'sittingText':
            '$oppositeDirection${oppositeHeading.toStringAsFixed(1)}°',
        'facingText': '$direction${displayHeading.toStringAsFixed(1)}°',
        'sittingDetail': _getSittingDetail(displayHeading),
        'facingDetail': _getFacingDetail(displayHeading),
        'latitude': lat,
        'longitude': lon,
        'altitude': _altitude,
        'address': addrToSave,
        'lunarText': _getLunarDate(),
        'remarkText': _measureRemarkController.text.trim(),
      };

      final resp = await http
          .post(
            Uri.parse('$_baseUrl/cp/measureRecord'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              if (user.token.isNotEmpty)
                'Authorization': 'Bearer ${user.token}',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 60));

      if (!mounted) return;

      Map<String, dynamic> decoded;
      try {
        decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (_) {
        await _showMeasureRecordAlert(
          '保存失败',
          '服务器响应异常（${resp.statusCode}）',
        );
        return;
      }

      final code = decoded['code'];
      final msg = decoded['msg']?.toString() ?? '';
      final ok = resp.statusCode == 200 && (code == 200 || code == '200');

      if (ok) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('测量记录已保存')),
        );
      } else {
        await _showMeasureRecordAlert(
          '保存失败',
          msg.isNotEmpty ? msg : '状态码 ${resp.statusCode}',
        );
      }
    } on TimeoutException {
      if (!mounted) return;
      await _showMeasureRecordAlert('保存失败', '请求超时，请检查网络后重试');
    } catch (e) {
      if (!mounted) return;
      await _showMeasureRecordAlert('保存失败', e.toString());
    } finally {
      _setSavingMeasureRecord(false);
    }
  }

  // 构建信息卡片
  Widget _buildInfoCard(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  // 构建旋转调整面板
  Widget _buildRotationPanel() {
    return Listener(
      onPointerDown: (event) {
        print('指针按下 - 锁定状态: $_isLocked');
      },
      onPointerMove: (event) {
        // 上下滑动调整角度
        if (!_isLocked) {
          return;
        }

        print('指针移动 - delta.dy: ${event.delta.dy}, 锁定状态: $_isLocked');
        double sensitivity = 0.5; // 灵敏度
        double delta = -event.delta.dy * sensitivity;
        // 连续累加偏移量，不做 360° 智能回绕/夹取，支持持续同向旋转
        double newOffset = _compassRotationOffset + delta;

        if ((newOffset - _compassRotationOffset).abs() > 0.01) {
          setState(() {
            _compassRotationOffset = newOffset;
          });
          print('旋转偏移更新: ${_compassRotationOffset.toStringAsFixed(1)}°, 基础角度: ${_lockedHeading.toStringAsFixed(1)}°, 最终角度: ${(_lockedHeading + _compassRotationOffset) % 360}');
        }
      },
      onPointerUp: (event) {
        print('指针抬起，最终偏移: ${_compassRotationOffset.toStringAsFixed(1)}°');
      },
      child: GestureDetector(
        onTap: () {
          print('透明条框被点击了');
        },
        onPanStart: (details) {
          print('开始滑动调整罗盘角度 - onPanStart, 锁定状态: $_isLocked');
        },
        onPanUpdate: (details) {
          // 上下滑动调整角度
          // 向上滑动增加角度，向下滑动减少角度
          print('滑动中 - delta.dy: ${details.delta.dy}, 锁定状态: $_isLocked');

          if (!_isLocked) {
            print('未锁定状态，无法调整');
            return;
          }

          double sensitivity = 0.5; // 灵敏度
          double delta = -details.delta.dy * sensitivity;
          // 连续累加偏移量，不做 360° 智能回绕/夹取，支持持续同向旋转
          double newOffset = _compassRotationOffset + delta;

          if ((newOffset - _compassRotationOffset).abs() > 0.01) {
            setState(() {
              _compassRotationOffset = newOffset;
            });
            print('旋转偏移更新: ${_compassRotationOffset.toStringAsFixed(1)}°, 基础角度: ${_lockedHeading.toStringAsFixed(1)}°');
          }
        },
        onPanEnd: (details) {
          print('滑动结束，最终偏移: ${_compassRotationOffset.toStringAsFixed(1)}°');
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
        width: 60,
        constraints: const BoxConstraints(
          minHeight: 250, // 最小高度，确保能包住所有文字
        ),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.4), // 增加可见性
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withOpacity(0.5),
            width: 2, // 增加边框宽度
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 提示文字（竖向显示，每个字一行）
            ...'上下滑动此处调整罗盘角度'.split('').map((char) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Text(
                char,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            )),
          ],
        ),
        ),
      ),
    );
  }

  // 显示罗盘旋转调整对话框（已废弃，保留以防需要）
  void _showCompassRotationDialog() {
    double tempRotationOffset = _compassRotationOffset;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.5,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // 标题栏
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Colors.grey, width: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '调整罗盘角度',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
                // 内容区域
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // 提示文字
                        const Text(
                          '上下滑动此处调整罗盘角度',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 40),
                        // 角度显示
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${tempRotationOffset.toStringAsFixed(1)}°',
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        // 滑动条
                        Slider(
                          value: tempRotationOffset,
                          min: -180.0,
                          max: 180.0,
                          divisions: 360,
                          label: '${tempRotationOffset.toStringAsFixed(1)}°',
                          onChanged: (value) {
                            setModalState(() {
                              tempRotationOffset = value;
                            });
                            // 实时更新罗盘显示
                            setState(() {
                              _compassRotationOffset = value;
                            });
                          },
                        ),
                        const SizedBox(height: 20),
                        // 快捷按钮
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ElevatedButton(
                              onPressed: () {
                                setModalState(() {
                                  tempRotationOffset = -90.0;
                                });
                                setState(() {
                                  _compassRotationOffset = -90.0;
                                });
                              },
                              child: const Text('-90°'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                setModalState(() {
                                  tempRotationOffset = 0.0;
                                });
                                setState(() {
                                  _compassRotationOffset = 0.0;
                                });
                              },
                              child: const Text('0°'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                setModalState(() {
                                  tempRotationOffset = 90.0;
                                });
                                setState(() {
                                  _compassRotationOffset = 90.0;
                                });
                              },
                              child: const Text('90°'),
                            ),
                          ],
                        ),
                        const Spacer(),
                        // 保存按钮
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _compassRotationOffset = tempRotationOffset;
                                _isLocked = true; // 保存后锁定
                                _lockedHeading = _heading;
                              });
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text(
                              '保存 测量',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 默认提示中「透地平分六十龙」当前命中的坐龙名（如 `甲子`）。
  String? _touDiPingFenSixtyDragonSitting({
    required double sittingDeg,
    required double facingDialDeg,
  }) {
    for (final e in _defaultTipJsonEntries) {
      if (e.displayName != '透地平分六十龙') continue;
      final row = DefaultTipJsonCatalog.matchRowData(
        sittingDegree: sittingDeg,
        facingDialDegree: facingDialDeg,
        root: e.root,
        layerName: e.displayName,
      );
      final zuo = row?['坐'];
      if (zuo is String && zuo.isNotEmpty) return zuo;
      return null;
    }
    return null;
  }
}

// 十字线绘制器
class CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // 绘制十字线
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

// 指南针指针绘制器
class CompassNeedlePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill;

    final path = Path();
    final center = Offset(size.width / 2, size.height / 2);

    // 绘制红色指针（指向北方）
    paint.color = Colors.red;
    path.moveTo(center.dx, center.dy - size.height / 2);
    path.lineTo(center.dx - 8, center.dy);
    path.lineTo(center.dx, center.dy + 5);
    path.lineTo(center.dx + 8, center.dy);
    path.close();
    canvas.drawPath(path, paint);

    // 绘制白色指针（指向南方）
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

/// 中心水平仪底盘绘制（无图片）
class _CenterLevelDiscPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 背景
    final bgPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, bgPaint);

    // 外圈描边
    final borderPaint = Paint()
      ..color = Colors.black.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius - 1, borderPaint);

    // 十字线
    final crossPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(center.dx - radius, center.dy),
      Offset(center.dx + radius, center.dy),
      crossPaint,
    );
    canvas.drawLine(
      Offset(center.dx, center.dy - radius),
      Offset(center.dx, center.dy + radius),
      crossPaint,
    );

    // 简单刻度（8个方向短线）
    final tickPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 8; i++) {
      final angle = i * (pi / 4);
      final p1 = Offset(
        center.dx + (radius - 10) * cos(angle),
        center.dy + (radius - 10) * sin(angle),
      );
      final p2 = Offset(
        center.dx + (radius - 18) * cos(angle),
        center.dy + (radius - 18) * sin(angle),
      );
      canvas.drawLine(p1, p2, tickPaint);
    }

    // 中心点
    final dotPaint = Paint()..color = Colors.black.withOpacity(0.25);
    canvas.drawCircle(center, 3, dotPaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

// -----------------------------------------------------------------------------
// 智能提示 JSON 解析（内联本文件，避免额外 dart 文件在本机未被 IDE 识别）
// -----------------------------------------------------------------------------

/// 方位规则未命中时，将对应 `.json` 根对象展开为可读文本，与源文件内容一致。
String _formatOtherTipJsonFallback(dynamic root, {int depth = 0, int maxChars = 28000}) {
  if (depth > 14) return '…\n';
  final buf = StringBuffer();
  void emit(String s) {
    if (buf.length >= maxChars) return;
    final left = maxChars - buf.length;
    buf.write(s.length <= left ? s : s.substring(0, left));
  }

  void fmt(dynamic node, int d) {
    if (buf.length >= maxChars) return;
    final pad = '  ' * d;
    if (node == null) {
      emit('${pad}null\n');
    } else if (node is String || node is num || node is bool) {
      emit('$pad$node\n');
    } else if (node is List) {
      for (final item in node) {
        if (buf.length >= maxChars) return;
        if (item is Map || item is List) {
          emit('$pad•\n');
          fmt(item, d + 1);
        } else {
          emit('$pad• ${item}\n');
        }
      }
    } else if (node is Map) {
      for (final e in node.entries) {
        if (buf.length >= maxChars) return;
        final k = e.key.toString();
        final v = e.value;
        if (v is Map || v is List) {
          emit('${pad}【$k】\n');
          fmt(v, d + 1);
        } else {
          emit('$pad$k：$v\n');
        }
      }
    } else {
      emit('$pad$node\n');
    }
  }

  fmt(root, depth);
  if (buf.length >= maxChars) {
    emit('\n…（内容过长，已截断）');
  }
  return buf.toString().trimRight();
}

OtherTipResolved? _resolveOtherTipForDetailPage(
  OtherTipJsonEntry entry, {
  required String sittingChar,
  required String facingChar,
  required double sittingDeg,
  required double facingDialDeg,
  String? touDiPingFenLongZuo,
}) {
  return _tipResolveInner(
    fileStem: entry.displayName,
    root: entry.root,
    sittingChar: sittingChar,
    facingChar: facingChar,
    sittingDeg: sittingDeg,
    facingDialDeg: facingDialDeg,
    touDiPingFenLongZuo: touDiPingFenLongZuo,
  );
}

String? _tipMatchCompositeMapKey(Map<String, dynamic> map, String composite) {
  for (final k in map.keys) {
    if (k == composite) return k;
    final parts = k.split(RegExp(r'[,，]'));
    for (final p in parts) {
      if (p.trim() == composite) return k;
    }
  }
  return null;
}

String _tipGongForSitting(String s) {
  if ('壬子癸'.contains(s)) return '坎宫';
  if ('丑艮寅'.contains(s)) return '艮宫';
  if ('甲卯乙'.contains(s)) return '震宫';
  if ('辰巽巳'.contains(s)) return '巽宫';
  if ('丙午丁'.contains(s)) return '离宫';
  if ('未坤申'.contains(s)) return '坤宫';
  if ('庚酉辛'.contains(s)) return '兑宫';
  if ('戌乾亥'.contains(s)) return '乾宫';
  return '坎宫';
}

String? _tipGuaWaterGroupForSitting(String s) {
  if ('壬子癸'.contains(s)) return '坎卦水';
  if ('丑艮寅'.contains(s)) return '艮卦水';
  if ('甲卯乙'.contains(s)) return '震卦水';
  if ('辰巽巳'.contains(s)) return '巽卦水';
  if ('丙午丁'.contains(s)) return '离卦水';
  if ('未坤申'.contains(s)) return '坤卦水';
  if ('庚酉辛'.contains(s)) return '兑卦水';
  if ('戌乾亥'.contains(s)) return '乾卦水';
  return null;
}

String _tipFormatFenjinDetail(Map<String, dynamic> m) {
  final buf = StringBuffer();
  final shi = m['诗'];
  if (shi is String && shi.isNotEmpty) {
    buf.writeln(shi);
  }
  final details = m['详解'];
  if (details is List) {
    if (buf.isNotEmpty) buf.writeln();
    for (final line in details) {
      buf.writeln(line);
    }
  }
  return buf.toString().trim();
}

dynamic _tipFindJinSuoShaJue(dynamic node, String sitting) {
  final target = '${sitting}山砂诀';
  if (node is Map) {
    final mm = Map<String, dynamic>.from(node);
    if (mm.containsKey(target)) return mm[target];
    for (final v in mm.values) {
      final r = _tipFindJinSuoShaJue(v, sitting);
      if (r != null) return r;
    }
  }
  return null;
}

String _tipFormatJinSuoBlock(dynamic block) {
  if (block is! Map) return block?.toString() ?? '';
  final m = Map<String, dynamic>.from(block);
  final buf = StringBuffer();
  for (final key in ['诗', '释义', '总结', '释义歌']) {
    final v = m[key];
    if (v is String && v.isNotEmpty) {
      if (buf.isNotEmpty) buf.writeln();
      buf.writeln(v);
    }
  }
  return buf.toString().trim();
}

String _tipFormatShanXiangDetail(Map<String, dynamic> m) {
  final buf = StringBuffer();
  const keys = ['坐向', '座山度数', '较旺方位', '较差方位', '普通位置', '说明'];
  for (final k in keys) {
    final v = m[k];
    if (v is String && v.isNotEmpty) {
      buf.writeln('$k：$v');
    }
  }
  return buf.toString().trim();
}

String _tipFormatWuXingMap(Map<String, dynamic> m) {
  final buf = StringBuffer();
  for (final e in m.entries) {
    buf.writeln('${e.key}：${e.value}');
  }
  return buf.toString().trim();
}

String _tipFormatLiuShiLongEntry(dynamic entry) {
  if (entry is! List) return entry?.toString() ?? '';
  final parts =
      entry.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts[0];
  final tag = parts.last;
  final desc = parts.sublist(0, parts.length - 1).join('');
  if (tag.length <= 8 && !tag.contains('。')) {
    return desc.isEmpty ? tag : '$desc\n（$tag）';
  }
  return parts.join('\n');
}

dynamic _tipFindLiuShiLongEntry(Map<String, dynamic> map, String longName) {
  if (map.containsKey(longName)) return map[longName];
  for (final node in map.values) {
    if (node is Map) {
      final mm = Map<String, dynamic>.from(node);
      if (mm.containsKey(longName)) return mm[longName];
    }
  }
  return null;
}

OtherTipResolved? _tipResolveInner({
  required String fileStem,
  required dynamic root,
  required String sittingChar,
  required String facingChar,
  required double sittingDeg,
  required double facingDialDeg,
  String? touDiPingFenLongZuo,
}) {
  final composite = '$sittingChar山$facingChar向';

  switch (fileStem) {
    case '分金提示':
      if (root is! Map<String, dynamic>) return null;
      final map = Map<String, dynamic>.from(root);
      final hitKey = _tipMatchCompositeMapKey(map, composite);
      if (hitKey == null) return null;
      final block = map[hitKey];
      if (block is! Map) return null;
      return OtherTipResolved(
        title: composite,
        body: _tipFormatFenjinDetail(Map<String, dynamic>.from(block)),
      );

    case '二十四山向':
      if (root is! Map<String, dynamic>) return null;
      final map = Map<String, dynamic>.from(root);
      final hitKey = map.containsKey(composite)
          ? composite
          : _tipMatchCompositeMapKey(map, composite);
      if (hitKey == null) return null;
      final block = map[hitKey];
      if (block is! Map) return null;
      final body = _tipFormatShanXiangDetail(Map<String, dynamic>.from(block));
      if (body.isEmpty) return null;
      return OtherTipResolved(title: composite, body: body);

    case '二十四山砂':
    case '纳甲辅星水法':
      if (root is! Map<String, dynamic>) return null;
      final map = Map<String, dynamic>.from(root);
      final hitKey = map.containsKey(composite)
          ? composite
          : _tipMatchCompositeMapKey(map, composite);
      if (hitKey == null) return null;
      final raw = map[hitKey];
      if (raw == null) return null;
      if (raw is List) {
        final body = raw.map((e) => e.toString()).join('\n');
        return OtherTipResolved(title: composite, body: body);
      }
      return OtherTipResolved(title: composite, body: raw.toString());

    case '五行提示':
      if (root is! Map<String, dynamic>) return null;
      final map = Map<String, dynamic>.from(root);
      final key = '$sittingChar山';
      final block = map[key];
      if (block is! Map) return null;
      return OtherTipResolved(
        title: key,
        body: _tipFormatWuXingMap(Map<String, dynamic>.from(block)),
      );

    case '二十四山砂水断语':
      if (root is! Map<String, dynamic>) return null;
      final map = Map<String, dynamic>.from(root);
      final kFacing = '$facingChar位';
      final kSitting = '$sittingChar位';
      dynamic raw = map[kFacing];
      var title = kFacing;
      if (raw == null) {
        raw = map[kSitting];
        title = kSitting;
      }
      if (raw == null) return null;
      return OtherTipResolved(title: title, body: raw.toString());

    case '二十四位水法诀':
      if (root is! Map<String, dynamic>) return null;
      final map = Map<String, dynamic>.from(root);
      final group = _tipGuaWaterGroupForSitting(sittingChar);
      if (group == null) return null;
      final sub = map[group];
      if (sub is! Map<String, dynamic>) return null;
      final mm = Map<String, dynamic>.from(sub);
      final line = mm[sittingChar];
      if (line == null) return null;
      return OtherTipResolved(
        title: '$group · $sittingChar',
        body: line.toString(),
      );

    case '二十四山宜忌':
      if (root is! Map<String, dynamic>) return null;
      final map = Map<String, dynamic>.from(root);
      final gong = _tipGongForSitting(sittingChar);
      final sub = map[gong];
      if (sub is! Map<String, dynamic>) return null;
      final mm = Map<String, dynamic>.from(sub);
      final key = '$sittingChar山';
      final raw = mm[key];
      if (raw == null) return null;
      final body = raw is List
          ? raw.map((e) => e.toString()).join('\n')
          : raw.toString();
      return OtherTipResolved(title: '$gong · $key', body: body);

    case '金锁玉关':
      final block = _tipFindJinSuoShaJue(root, sittingChar);
      if (block == null) return null;
      final body = _tipFormatJinSuoBlock(block);
      if (body.isEmpty) return null;
      return OtherTipResolved(
        title: composite,
        body: body,
      );

    case '山水六十龙':
      if (root is! Map<String, dynamic>) return null;
      final map = Map<String, dynamic>.from(root);
      final longName = touDiPingFenLongZuo;
      if (longName == null || longName.isEmpty) return null;
      final entryNode = _tipFindLiuShiLongEntry(map, longName);
      if (entryNode == null) return null;
      final body = _tipFormatLiuShiLongEntry(entryNode);
      if (body.isEmpty) return null;
      return OtherTipResolved(
        title: longName,
        body: body,
      );

    default:
      final fallback = DefaultTipJsonCatalog.matchRow(
        sittingDegree: sittingDeg,
        facingDialDegree: facingDialDeg,
        root: root,
      );
      if (fallback != null && fallback.isNotEmpty) {
        return OtherTipResolved(title: fileStem, body: fallback);
      }
      return null;
  }
}
