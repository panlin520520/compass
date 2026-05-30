import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'dart:ui' as ui;
import 'dart:async';

import 'api_config.dart';

class LubanRulerPage extends StatefulWidget {
  const LubanRulerPage({super.key});

  @override
  State<LubanRulerPage> createState() => _LubanRulerPageState();
}

class _LubanRulerPageState extends State<LubanRulerPage> {
  // 尺子区域宽度倍数（相对于屏幕宽度）
  static const double _rulerWidthMultiplier = 200.0;
  
  // 4张图的统一缩放比例（用于整体缩小图片）
  static const double _imageScaleFactor = 0.415; // 缩小到75%
  
  // 鲁班尺类型
  String _lubanType = '现代鲁班尺';
  
  // 鲁班尺类型数据
  final List<Map<String, String>> _lubanTypes = [
    {
      'name': '现代鲁班尺',
      'length': '42.9',
      'description': '现代版鲁班尺，长度为42.9cm，这是目前最常用的鲁班尺版本。它基于传统的鲁班尺标准，适用于现代建筑和装修测量。',
    },
    {
      'name': '故宫鲁班尺',
      'length': '46.08',
      'description': '故宫鲁班尺（明清尺），长度为46.08cm，木工尺（营造尺）长32cm。这个版本是根据故宫里的鲁班尺而来，体现了明清时期的度量标准。',
    },
    {
      'name': '赣南鲁班尺',
      'length': '50.4',
      'description': '赣南鲁班尺（客家尺），长度为50.4cm，木工尺（营造尺）长35cm。主要在赣南、粤东地区使用，是客家文化中的重要度量工具。',
    },
  ];
  
  // 根据鲁班尺类型获取刻度图片路径
  String _getScaleImagePath() {
    switch (_lubanType) {
      case '现代鲁班尺':
        return 'assets/luban/xiandailubanScale.png';
      case '故宫鲁班尺':
        return 'assets/luban/gugonglubanScale.png';
      case '赣南鲁班尺':
        return 'assets/luban/gannanlubanScale.png';
      default:
        return 'assets/luban/xiandailubanScale.png';
    }
  }
  
  // 根据鲁班尺类型获取吉凶信息图片路径
  String _getFortuneImagePath() {
    switch (_lubanType) {
      case '现代鲁班尺':
        return 'assets/luban/xiandailuban.png';
      case '故宫鲁班尺':
        return 'assets/luban/gugongluban.png';
      case '赣南鲁班尺':
        return 'assets/luban/gannanluban.png';
      default:
        return 'assets/luban/xiandailuban.png';
    }
  }
  
  // 根据鲁班尺类型获取格数
  int _getLubanScaleGridCount() {
    switch (_lubanType) {
      case '现代鲁班尺':
        return 17; // 现代鲁班尺有17格
      case '故宫鲁班尺':
        return 15; // 故宫鲁班尺有15格
      case '赣南鲁班尺':
        return 15; // 赣南鲁班尺有15格
      default:
        return 17;
    }
  }
  
  // 根据鲁班尺类型获取总长度（厘米）
  double _getLubanTotalLength() {
    switch (_lubanType) {
      case '现代鲁班尺':
        return 42.67; // 现代鲁班尺长度为42.9厘米
      case '故宫鲁班尺':
        return 46.08; // 故宫鲁班尺长度为46.08厘米
      case '赣南鲁班尺':
        return 50.4; // 赣南鲁班尺长度为50.4厘米
      default:
        return 42.9; // 默认使用现代鲁班尺长度
    }
  }
  
  // 滚动控制器
  final ScrollController _scrollController = ScrollController();
  
  // 当前厘米值（使用ValueNotifier实现轻量级更新）
  final ValueNotifier<double> _currentCentimetersNotifier = ValueNotifier<double>(0.00);
  
  // 鲁班和丁兰的吉凶信息（使用ValueNotifier实现轻量级更新）
  final ValueNotifier<String> _lubanFortuneNotifier = ValueNotifier<String>('財德');
  final ValueNotifier<String> _dinglanFortuneNotifier = ValueNotifier<String>('福星');
  
  // 兼容性：保持原有变量用于其他地方
  double get _currentCentimeters => _currentCentimetersNotifier.value;
  String get _lubanFortune => _lubanFortuneNotifier.value;
  String get _dinglanFortune => _dinglanFortuneNotifier.value;
  
  // 像素到厘米的转换比例（需要根据实际尺子图片校准）
  double _pixelsPerCentimeter = 8.0;

  /// biaochi 资源内红线横向位置（相对图片宽度，0.5 为正中竖线）
  static const double _biaochiRedLineXRatio = 0.5;

  /// 尺子内容区压缩高度（顶底刻度 + 吉凶 + 丁兰叠加），供 head/biaochi 对齐
  double _rulerDisplayHeight = 0.0;

  static double _scaledImageWidth(Size imageSize, double displayHeight) {
    if (imageSize.height <= 0) return 0;
    return (imageSize.width / imageSize.height) * displayHeight;
  }

  static double _scaledImageHeight(Size imageSize) {
    return imageSize.height.toDouble() * _imageScaleFactor;
  }

  /// 尺子内容区高度 = 顶/底刻度条 + 吉凶图 + 丁兰图（使 dinglan 上边与吉凶图下边重合）
  static double _computeRulerContentHeight(
    double lubanScaleHeight,
    double fortuneHeight,
    double dinglanHeight,
    double dingLanScaleHeight,
  ) {
    return lubanScaleHeight + fortuneHeight + dinglanHeight + dingLanScaleHeight;
  }

  Future<List<Size>> _loadRulerLayerSizes() {
    return Future.wait([
      _getImageSize(_getScaleImagePath()),
      _getImageSize(_getFortuneImagePath()),
      _getImageSize('assets/luban/dinglan.png'),
      _getImageSize('assets/luban/dingLanScale.png'),
    ]);
  }

  Widget _transparentHeadSpacer(double contentHeight) {
    return SizedBox(
      height: contentHeight,
      child: AppAssetImage(
        assetPath: 'assets/luban/head.png',
        fit: BoxFit.fitHeight,
        opacity: const AlwaysStoppedAnimation(0.0),
        errorBuilder: (context, error, stackTrace) {
          return const SizedBox.shrink();
        },
      ),
    );
  }

  /// 左移 biaochi，使红线落在 head.png 右缘
  double _biaochiTranslateXAtHeadRightEdge(
    double displayHeight,
    Size biaochiSize,
  ) {
    return -_scaledImageWidth(biaochiSize, displayHeight) * _biaochiRedLineXRatio;
  }

  void _syncRulerDisplayHeight(double height) {
    if ((height - _rulerDisplayHeight).abs() < 0.5) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if ((height - _rulerDisplayHeight).abs() >= 0.5) {
        setState(() => _rulerDisplayHeight = height);
      }
    });
  }
  
  // xiandailubanScale.png的像素到厘米转换比例（每张图片宽度对应1厘米）
  double _xianDaiPixelsPerCentimeter = 8.0;
  
  // 是否正在通过输入调整（避免循环更新）
  bool _isAdjusting = false;

  // 主显示单位：false=厘米，true=英寸（现代鲁班尺）或尺（其他类型）
  bool _useAlternateUnit = false;

  static const double _cmPerInch = 2.54;
  static const double _cmPerChi = 100.0 / 3.0; // 市尺

  bool get _isModernLuban => _lubanType == '现代鲁班尺';

  String get _alternateUnitLabel => _isModernLuban ? '英寸' : '尺';

  String get _primaryUnitLabel => _useAlternateUnit ? _alternateUnitLabel : '厘米';

  double _cmToAlternate(double cm) =>
      _isModernLuban ? cm / _cmPerInch : cm / _cmPerChi;

  double _alternateToCm(double value) =>
      _isModernLuban ? value * _cmPerInch : value * _cmPerChi;

  double _displayValueFromCm(double cm) =>
      _useAlternateUnit ? _cmToAlternate(cm) : cm;

  String _formatDisplayValue(double cm) =>
      _displayValueFromCm(cm).toStringAsFixed(2);

  double? _parseInputToCm(String value) {
    final parsed = double.tryParse(value.trim());
    if (parsed == null || parsed < 0) return null;
    final cm = _useAlternateUnit ? _alternateToCm(parsed) : parsed;
    if (cm > 1000) return null;
    return cm;
  }

  void _toggleDisplayUnit() {
    setState(() => _useAlternateUnit = !_useAlternateUnit);
  }

  Widget _buildDualUnitLabels(double cm) {
    final alt = _cmToAlternate(cm);
    final altLabel = _alternateUnitLabel;
    return Text(
      '$altLabel: ${alt.toStringAsFixed(2)}  厘米: ${cm.toStringAsFixed(2)}',
      style: TextStyle(
        fontSize: 13,
        color: Colors.black.withOpacity(0.75),
        fontWeight: FontWeight.w500,
      ),
    );
  }
  
  // 输入框控制器（用于手动输入厘米值）
  final TextEditingController _centimetersInputController = TextEditingController();
  
  // head.png的宽度（用于计算滚动偏移）
  double _headWidth = 0.0;
  
  // 是否已初始化尺子比例
  bool _isInitialized = false;
  
  // 当前屏幕方向（用于检测方向变化）
  Orientation? _currentOrientation;
  
  // 当前屏幕尺寸（用于检测尺寸变化）
  Size? _lastScreenSize;
  
  // 初始化定时器（用于延迟初始化）
  Timer? _initTimer;
  
  // 滚动更新防抖定时器（用于减少setState调用频率，避免影响滚动惯性）
  Timer? _scrollUpdateTimer;
  
  // 上次更新的滚动位置（用于判断是否需要更新）
  double _lastUpdateOffset = 0.0;
  
  // 上次滚动时间（用于判断滚动速度）
  DateTime? _lastScrollTime;
  
  // 是否在快速滚动中（用于判断是否应该更新UI）
  bool _isFastScrolling = false;
  
  // 滚动停止检测定时器（用于在滚动停止时强制更新UI）
  Timer? _scrollEndTimer;
  
  // 上次滚动位置（用于检测滚动是否停止）
  double _lastScrollOffset = 0.0;
  
  // 待更新的厘米值（避免频繁setState）
  final double _pendingCentimeters = 0.0;
  
  // 是否正在处理setState（避免重复调用）
  final bool _isUpdatingUI = false;
  
  // 上次更新UI的时间（用于限制更新频率）
  DateTime? _lastUIUpdateTime;
  
  // 获取图片尺寸（从后端静态资源加载）
  Future<Size> _getImageSize(String imagePath) async {
    return getAppAssetImageSize(imagePath);
  }
  
  @override
  void initState() {
    super.initState();
    // 1. 锁定横屏，禁止竖屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // 使用沉浸式全屏模式，系统UI会在短暂显示后自动隐藏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // 确保滚动视图从左侧开始
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
    // 监听滚动位置变化
    _scrollController.addListener(_onScroll);
    // 初始化输入框的值
    _centimetersInputController.text = '0.00';
  }
  
  // 滚动监听（确保UI实时更新，同时保持滚动流畅性）
  void _onScroll() {
    if (!_scrollController.hasClients || _isAdjusting) return;
    
    final scrollOffset = _scrollController.offset;
    
    // 计算位置变化量
    final offsetDelta = (scrollOffset - _lastUpdateOffset).abs();
    
    // 如果滚动位置变化很小（小于0.3像素），跳过更新（避免过度更新）
    if (offsetDelta < 0.3) {
      return;
    }
    
    // 计算新的厘米值（尺子刻度从滚动位置0开始，不需要减去headWidth）
    final pixelsPerCm = _pixelsPerCentimeter > 0 ? _pixelsPerCentimeter : 8.0;
    final newCentimeters = (scrollOffset / pixelsPerCm).clamp(0.0, 1000.0);
    
    // 检查数据是否有变化（降低阈值，确保更频繁更新）
    final centimetersDelta = (newCentimeters - _currentCentimeters).abs();
    
    // 取消之前的定时器
    _scrollUpdateTimer?.cancel();
    
    // 根据位置变化量决定更新频率
    // 位置变化越大，更新越频繁，确保实时性
    if (offsetDelta > 20.0) {
      // 位置变化很大，快速更新（15ms延迟）
      _isFastScrolling = true;
      _scrollUpdateTimer = Timer(const Duration(milliseconds: 15), () {
        if (mounted && _scrollController.hasClients && !_isAdjusting) {
          _updateUIFromScrollDirect(_scrollController.offset);
        }
      });
    } else if (offsetDelta > 5.0) {
      // 位置变化中等，中等频率更新（25ms延迟）
      _isFastScrolling = true;
      _scrollUpdateTimer = Timer(const Duration(milliseconds: 25), () {
        if (mounted && _scrollController.hasClients && !_isAdjusting) {
          _updateUIFromScrollDirect(_scrollController.offset);
        }
      });
    } else {
      // 位置变化较小，正常频率更新（40ms延迟）
      _isFastScrolling = false;
      _scrollUpdateTimer = Timer(const Duration(milliseconds: 40), () {
        if (mounted && _scrollController.hasClients && !_isAdjusting) {
          _updateUIFromScrollDirect(_scrollController.offset);
        }
      });
    }
    
    // 检测滚动是否停止
    final scrollOffsetDelta = (scrollOffset - _lastScrollOffset).abs();
    _lastScrollOffset = scrollOffset;
    
    // 如果滚动位置没有变化，可能是滚动停止了，确保最后更新一次UI
    if (scrollOffsetDelta < 0.3) {
      _scrollEndTimer?.cancel();
      _scrollEndTimer = Timer(const Duration(milliseconds: 80), () {
        if (mounted && _scrollController.hasClients && !_isAdjusting) {
          final currentOffset = _scrollController.offset;
          if ((currentOffset - _lastScrollOffset).abs() < 1.0) {
            _isFastScrolling = false;
            _updateUIFromScrollDirect(currentOffset);
          }
        }
      });
    } else {
      _scrollEndTimer?.cancel();
    }
  }
  
  // 直接更新UI（使用ValueNotifier实现轻量级更新，不影响滚动）
  void _updateUIFromScrollDirect(double scrollOffset) {
    if (!mounted || _isAdjusting) return;
    
    // 计算厘米值（尺子刻度从滚动位置0开始，不需要减去headWidth）
    final pixelsPerCm = _pixelsPerCentimeter > 0 ? _pixelsPerCentimeter : 8.0;
    final centimeters = (scrollOffset / pixelsPerCm).clamp(0.0, 1000.0);
    
    // 检查数据是否有变化（降低阈值，确保更频繁更新）
    final centimetersDelta = (centimeters - _currentCentimetersNotifier.value).abs();
    
    // 如果数据变化很小（小于0.01厘米），跳过更新（避免过度更新）
    if (centimetersDelta < 0.01) {
      return;
    }
    
    // 更新上次更新位置
    _lastUpdateOffset = scrollOffset;
    
    // 直接更新ValueNotifier，这会触发ValueListenableBuilder重建，但不影响滚动
    // ValueNotifier的更新是异步且轻量级的，不会阻塞滚动
    _currentCentimetersNotifier.value = centimeters;
    
    // 更新输入框显示值（只在输入框没有焦点时更新，避免用户正在输入时被覆盖）
    // 这个更新会在 ValueListenableBuilder 的 builder 中处理
    
    // 更新吉凶信息（只更新值，ValueListenableBuilder会自动处理UI更新）
    _updateFortuneInfo(centimeters);
  }
  
  // 更新吉凶信息（根据厘米值查找对应的鲁班和丁兰吉凶）
  // 支持现代鲁班尺、故宫鲁班尺、赣南鲁班尺三种类型
  void _updateFortuneInfo(double centimeters) {
    String newLubanFortune;
    String newDinglanFortune;
    
    // 根据当前鲁班尺类型获取总长度
    // 现代鲁班尺：42.9厘米
    // 故宫鲁班尺：46.08厘米
    // 赣南鲁班尺：50.4厘米
    final double lubanTotalLength = _getLubanTotalLength();
    
    // 所有鲁班尺类型都有8个大类，每个大类4个小类
    // 每个大类的长度 = 总长度 / 8
    // 每个小类的长度 = 大类长度 / 4
    final double lubanLargeSegment = lubanTotalLength / 8; // 每个大类的长度
    final double lubanSmallSegment = lubanLargeSegment / 4; // 每个小类的长度
    
    // 鲁班尺8个大类及其小类（所有类型都相同）
    final List<String> lubanLargeNames = ['财', '病', '离', '义', '官', '劫', '害', '本'];
    final List<List<String>> lubanSmallNames = [
      ['财德', '宝库', '六合', '迎福'],      // 财类：财德、宝库、六合、迎福
      ['退财', '公事', '牢执', '孤寡'],      // 病类：退财、公事、牢执、孤寡
      ['长库', '劫财', '官鬼', '失脱'],      // 离类：长库、劫财、官鬼、失脱
      ['添丁', '益利', '贵子', '大吉'],      // 义类：添丁、益利、贵子、大吉
      ['顺科', '横财', '进益', '富贵'],      // 官类：顺科、横财、进益、富贵
      ['死别', '退口', '离乡', '财失'],      // 劫类：死别、退口、离乡、财失
      ['灾至', '死绝', '病临', '口舌'],      // 害类：灾至、死绝、病临、口舌
      ['财至', '登科', '进宝', '兴旺'],      // 本类：财至、登科、进宝、兴旺
    ];
    
    // 计算鲁班尺位置（取模运算，确保在当前类型的总长度范围内循环）
    // 例如：现代鲁班尺 43厘米 % 42.9 = 0.1，会重新从第一个大类开始
    // 例如：故宫鲁班尺 47厘米 % 46.08 = 0.92，在第一个大类内
    final double lubanPosition = centimeters % lubanTotalLength;
    
    // 计算属于第几个大类（0-7）
    // 通过除法取整得到大类索引
    final int lubanLargeIndex = (lubanPosition / lubanLargeSegment).floor().clamp(0, 7);
    
    // 计算在当前大类中的位置（取模运算，得到在当前大类中的偏移量）
    final double lubanSmallPosition = lubanPosition % lubanLargeSegment;
    
    // 计算属于第几个小类（0-3）
    // 通过除法取整得到小类索引
    final int lubanSmallIndex = (lubanSmallPosition / lubanSmallSegment).floor().clamp(0, 3);
    
    // 组合显示：大类-小类
    final String lubanLargeName = lubanLargeNames[lubanLargeIndex];
    final String lubanSmallName = lubanSmallNames[lubanLargeIndex][lubanSmallIndex];
    newLubanFortune = '$lubanLargeName-$lubanSmallName';
    
    // 丁兰尺的吉凶计算
    // 丁兰尺：39厘米为一个周期，10个大类，每个大类3.9厘米，每个小类0.975厘米
    const double dinglanTotalLength = 39.0; // 丁兰尺总长度39厘米
    const double dinglanLargeSegment = 39.0 / 10; // 每个大类长度3.9厘米
    const double dinglanSmallSegment = dinglanLargeSegment / 4; // 每个小类长度0.975厘米
    
    // 丁兰尺10个大类及其小类（每个大类4个小类，共40个小类）
    // 按照用户提供的顺序：丁、害、旺、苦、义、官、死、兴、失、财
    final List<String> dinglanLargeNames = ['丁', '害', '旺', '苦', '义', '官', '死', '兴', '失', '财'];
    final List<List<String>> dinglanSmallNames = [
      ['福星', '及第', '财旺', '登科'],        // 丁类：福星、及第、财旺、登科
      ['口舌', '病临', '死绝', '灾至'],        // 害类：口舌、病临、死绝、灾至
      ['天德', '喜事', '进宝', '纳福'],        // 旺类：天德、喜事、进宝、纳福
      ['失脱', '官鬼', '劫财', '无嗣'],        // 苦类：失脱、官鬼、劫财、无嗣
      ['大吉', '财旺', '益利', '天库'],        // 义类：大吉、财旺、益利、天库
      ['富贵', '进宝', '横财', '顺科'],        // 官类：富贵、进宝、横财、顺科
      ['离乡', '死别', '退丁', '失财'],        // 死类：离乡、死别、退丁、失财
      ['登科', '贵子', '添丁', '兴旺'],        // 兴类：登科、贵子、添丁、兴旺
      ['孤寡', '牢执', '公事', '退财'],        // 失类：孤寡、牢执、公事、退财
      ['迎福', '六合', '进宝', '财德'],        // 财类：迎福、六合、进宝、财德
    ];
    
    // 计算丁兰尺位置（取模运算，确保在0-39范围内循环）
    // 例如：40厘米 % 39 = 1，会重新从第一个大类开始
    // 例如：78厘米 % 39 = 0，正好两个周期，回到起点
    final double dinglanPosition = centimeters % dinglanTotalLength;
    
    // 计算属于第几个大类（0-9）
    // 每个大类3.9厘米，通过除法取整得到大类索引
    final int dinglanLargeIndex = (dinglanPosition / dinglanLargeSegment).floor().clamp(0, 9);
    
    // 计算在当前大类中的位置（取模运算，得到在当前大类中的偏移量）
    final double dinglanSmallPosition = dinglanPosition % dinglanLargeSegment;
    
    // 计算属于第几个小类（0-3）
    // 每个小类0.975厘米，通过除法取整得到小类索引
    final int dinglanSmallIndex = (dinglanSmallPosition / dinglanSmallSegment).floor().clamp(0, 3);
    
    // 组合显示：大类-小类
    final String dinglanLargeName = dinglanLargeNames[dinglanLargeIndex];
    final String dinglanSmallName = dinglanSmallNames[dinglanLargeIndex][dinglanSmallIndex];
    newDinglanFortune = '$dinglanLargeName-$dinglanSmallName';
    
    // 使用ValueNotifier更新状态（轻量级更新，不影响滚动）
    _lubanFortuneNotifier.value = newLubanFortune;
    _dinglanFortuneNotifier.value = newDinglanFortune;
  }
  
  void _restoreScrollToCentimeters(double centimeters) {
    final clampedCm = centimeters.clamp(0.0, 1000.0);
    final ppm = _pixelsPerCentimeter > 0 ? _pixelsPerCentimeter : 8.0;

    _currentCentimetersNotifier.value = clampedCm;
    _updateFortuneInfo(clampedCm);
    _centimetersInputController.text = _formatDisplayValue(clampedCm);

    void applyScroll() {
      if (!_scrollController.hasClients) return;
      final maxScroll = _scrollController.position.maxScrollExtent;
      final target = (clampedCm * ppm).clamp(0.0, maxScroll);
      _scrollController.jumpTo(target);
      _lastUpdateOffset = target;
    }

    applyScroll();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) applyScroll();
    });
  }

  // 初始化尺子比例
  Future<void> _initializeRulerScale(
    double screenHeight, {
    double? preserveCentimeters,
  }) async {
    try {
      final headSize = await _getImageSize('assets/luban/head.png');
      final layerSizes = await _loadRulerLayerSizes();
      final contentHeight = _computeRulerContentHeight(
        _scaledImageHeight(layerSizes[0]),
        _scaledImageHeight(layerSizes[1]),
        _scaledImageHeight(layerSizes[2]),
        _scaledImageHeight(layerSizes[3]),
      );
      
      if (headSize.height > 0 && contentHeight > 0) {
        _headWidth = (headSize.width / headSize.height) * contentHeight;
      }
      
      // 根据dingLanScale.png来计算像素到厘米的转换比例
      // dingLanScale.png一共有39大格，每一大格代表1厘米，所以整个图片宽度对应39厘米
      // 使用缩放后的图片尺寸计算
      final dingLanScaleImageSize = await _getImageSize('assets/luban/dingLanScale.png');
      
      if (dingLanScaleImageSize.width > 0) {
        // dingLanScale.png原始总宽度对应39厘米，缩放后宽度 = 原始宽度 * 缩放比例
        // 所以每厘米的像素数 = 缩放后宽度 / 39 = (原始宽度 * 缩放比例) / 39
        _pixelsPerCentimeter = (dingLanScaleImageSize.width * _imageScaleFactor) / 39.0;
      } else {
        // 如果获取图片尺寸失败，使用默认值
        _pixelsPerCentimeter = 8.0;
      }
      
      // 根据当前鲁班尺刻度图片来计算每格的像素
      // 不同鲁班尺类型有不同的格数：现代鲁班尺17格，故宫和赣南鲁班尺15格
      // 每一格代表1厘米，所以整个图片宽度对应格数厘米
      final lubanScaleImageSize = await _getImageSize(_getScaleImagePath());
      
      if (lubanScaleImageSize.width > 0) {
        // 获取当前鲁班尺类型的格数
        final gridCount = _getLubanScaleGridCount();
        
        // 当前鲁班尺刻度图片原始总宽度对应gridCount格（每格1厘米），缩放后宽度 = 原始宽度 * 缩放比例
        // 所以每格的像素数 = 缩放后宽度 / gridCount = (原始宽度 * 缩放比例) / gridCount
        _xianDaiPixelsPerCentimeter = (lubanScaleImageSize.width * _imageScaleFactor) / gridCount;
      } else {
        // 如果获取图片尺寸失败，使用默认值
        _xianDaiPixelsPerCentimeter = 8.0;
      }
      
      // 如果计算出的值太小或太大，使用默认值
      if (_pixelsPerCentimeter < 0.1 || _pixelsPerCentimeter > 100) {
        _pixelsPerCentimeter = 8.0;
      }
      
      _isInitialized = true;

      if (mounted) {
        setState(() {
          _rulerDisplayHeight = contentHeight;
        });
        final cmToRestore = preserveCentimeters ?? 0.0;
        _restoreScrollToCentimeters(cmToRestore);
      }
    } catch (e) {
      print('初始化尺子比例失败: $e');
      // 如果初始化失败，使用默认值
      _pixelsPerCentimeter = 8.0;
      _xianDaiPixelsPerCentimeter = 8.0;
      _isInitialized = true;
      if (mounted) {
        setState(() {});
      }
    }
  }
  
  // 动态计算底部padding，考虑系统UI的高度
  /// 尺子叠加层（biaochi 等）可用高度
  double _rulerOverlayHeight(
    BuildContext context,
    double layoutHeight,
    bool isLandscape,
  ) {
    const controlCore = 112.0;
    final bottomPad = _calculateBottomPadding(context, isLandscape);
    return (layoutHeight - 20 - 12 - controlCore - bottomPad)
        .clamp(60.0, layoutHeight);
  }

  double _calculateBottomPadding(BuildContext context, bool isLandscape) {
    final mediaQuery = MediaQuery.of(context);
    final systemPadding = mediaQuery.padding;
    
    // 横屏时，系统导航栏可能在右侧（systemPadding.right），也可能在底部（systemPadding.bottom）
    // 为了避免溢出，需要根据实际情况动态调整
    if (isLandscape) {
      // 横屏时，右侧导航栏通常占用 systemPadding.right
      // 底部padding需要预留足够空间，避免系统UI显示时溢出
      // 34像素是用户反馈的溢出值，我们增加一些余量
      if (systemPadding.bottom > 0) {
        return systemPadding.bottom + 10;
      } else if (systemPadding.right > 0) {
        // 如果有右侧padding（导航栏在右侧），也要预留一些底部空间
        return 34 + 10; // 34是溢出值，10是安全余量
      } else {
        return 19; // 默认值
      }
    } else {
      // 竖屏时，使用底部padding
      return systemPadding.bottom > 0 ? systemPadding.bottom + 10 : 19;
    }
  }
  
  // 显示鲁班尺类型选择器
  void _showLubanTypeSelector(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '切换鲁班尺版本',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            // 选项列表（使用Column而不是ListView，因为只有3个固定项）
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Column(
                  children: _lubanTypes.map((type) {
                    final isSelected = _lubanType == type['name'];
                    
                    return GestureDetector(
                      onTap: () {
                        final currentCm = _currentCentimetersNotifier.value;
                        setState(() {
                          _lubanType = type['name']!;
                          _useAlternateUnit = false;
                          // 切换类型后重新初始化尺子比例（保留当前厘米位置）
                          _isInitialized = false;
                          _pixelsPerCentimeter = 8.0;
                          _xianDaiPixelsPerCentimeter = 8.0;
                        });

                        Navigator.pop(context);
                        Future.delayed(const Duration(milliseconds: 100), () {
                          if (mounted) {
                            final screenHeight =
                                MediaQuery.of(context).size.height;
                            _initializeRulerScale(
                              screenHeight,
                              preserveCentimeters: currentCm,
                            );
                          }
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected 
                              ? const Color(0xFF00D4AA) // 青色背景（选中）
                              : Colors.white.withOpacity(0.1), // 半透明白色（未选中）
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected ? Colors.white : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            // 选中图标
                            if (isSelected)
                              const Padding(
                                padding: EdgeInsets.only(right: 10),
                                child: Icon(
                                  Icons.check_circle,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ),
                            // 内容
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${type['name']}${type['length']}',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      if (isSelected)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: const Text(
                                            '切换之',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    type['description']!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isSelected ? Colors.white.withOpacity(0.9) : Colors.white.withOpacity(0.7),
                                      height: 1.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // 调整当前显示单位的步进（内部仍以厘米驱动尺子）
  void _adjustCentimeters(double deltaInDisplayUnit) {
    final deltaCm =
        _useAlternateUnit ? _alternateToCm(deltaInDisplayUnit) : deltaInDisplayUnit;
    final newCentimeters =
        (_currentCentimetersNotifier.value + deltaCm).clamp(0.0, 1000.0);
    _scrollToCentimeters(newCentimeters);
  }
  
  // 根据厘米值滚动到对应位置
  void _scrollToCentimeters(double centimeters) {
    // 确保厘米值在合理范围内
    final clampedCentimeters = centimeters.clamp(0.0, 1000.0);
    
    // 获取像素到厘米的转换比例
    final pixelsPerCm = _pixelsPerCentimeter > 0 ? _pixelsPerCentimeter : 8.0;
    
    // 计算目标像素位置（尺子刻度从滚动位置0开始，不需要加上headWidth）
    // 因为从滚动位置计算厘米值时使用的是 scrollOffset / pixelsPerCm
    // 所以从厘米值计算滚动位置时应该使用 centimeters * pixelsPerCm
    final targetPixels = clampedCentimeters * pixelsPerCm;
    
    // 确保滚动位置有效
    if (!_scrollController.hasClients) {
      return;
    }
    
    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    final targetScrollOffset = targetPixels.clamp(0.0, maxScrollExtent);
    
    // 设置调整标志，避免滚动事件触发更新
    _isAdjusting = true;
    
    // 平滑滚动到目标位置
    _scrollController.animateTo(
      targetScrollOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    ).then((_) {
      // 滚动完成后，更新厘米值与鲁班/丁兰吉凶（滚动过程中 _isAdjusting 会屏蔽监听）
      if (mounted) {
        _isAdjusting = false;
        if (_scrollController.hasClients) {
          final actualOffset = _scrollController.offset;
          final actualCentimeters =
              (actualOffset / pixelsPerCm).clamp(0.0, 1000.0);
          _lastUpdateOffset = actualOffset;
          _currentCentimetersNotifier.value = actualCentimeters;
          _centimetersInputController.text = _formatDisplayValue(actualCentimeters);
          _updateFortuneInfo(actualCentimeters);
        }
      }
    });
  }
  
  // 处理输入完成（失去焦点或按回车）
  void _onCentimetersInputSubmitted(String value) {
    final inputCentimeters = _parseInputToCm(value);

    if (inputCentimeters != null) {
      _scrollToCentimeters(inputCentimeters);
      _centimetersInputController.text = _formatDisplayValue(inputCentimeters);
      FocusScope.of(context).unfocus();
    } else {
      _centimetersInputController.text =
          _formatDisplayValue(_currentCentimetersNotifier.value);
      FocusScope.of(context).unfocus();
    }
  }
  
  // 显示数值输入表单（从顶部显示，避免被键盘遮挡）
  void _showCentimetersInputSheet(BuildContext context) {
    final tempController = TextEditingController(
      text: _formatDisplayValue(_currentCentimetersNotifier.value),
    );
    
    // 使用 showGeneralDialog 从顶部显示表单
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭厘米值输入',
      barrierColor: Colors.black.withOpacity(0.3),
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.topCenter,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: double.infinity,
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5,
              ),
              margin: const EdgeInsets.only(top: 0),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
        child: Column(
          children: [
            // 顶部标题栏（参考图片样式）
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border(
                  bottom: BorderSide(color: Colors.grey[300]!, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  // 返回按钮
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black),
                    onPressed: () => Navigator.pop(context),
                  ),
                  // 当前值显示（参考图片中的"0.00"显示）
                  Expanded(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _currentCentimetersNotifier,
                      builder: (context, value, child) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildDualUnitLabels(value),
                            const SizedBox(height: 4),
                            Text(
                              '${_formatDisplayValue(value)} $_primaryUnitLabel',
                              style: const TextStyle(
                                fontSize: 20,
                                color: Colors.black,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  // 完成按钮（参考图片中的蓝色椭圆按钮）
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: TextButton(
                      onPressed: () {
                        final inputCentimeters =
                            _parseInputToCm(tempController.text);

                        if (inputCentimeters != null) {
                          _scrollToCentimeters(inputCentimeters);
                          Navigator.pop(context);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '请输入有效的$_primaryUnitLabel值（对应0-1000厘米）',
                              ),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        '完成',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 输入框区域（参考图片中的大输入框）
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: TextField(
                    controller: tempController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 56,
                      color: Colors.black,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 1.2,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.blue, width: 2),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                      hintText: '0.00',
                      hintStyle: TextStyle(
                        fontSize: 56,
                        color: Colors.grey[400],
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                    ],
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
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          )),
          child: child,
        );
      },
    );
  }
  
  // 构建整数厘米标记（用于dingLanScale.png）
  List<Widget> _buildCentimeterMarks(double screenWidth, double screenHeight, double headWidth, double pixelsPerCm, double markTop) {
    final List<Widget> marks = [];
    
    // 确保 pixelsPerCm 有合理的最小值
    if (pixelsPerCm < 1.0) {
      return marks;
    }
    
    // 计算整个尺子的总长度（像素）
    final totalRulerWidth = screenWidth * _rulerWidthMultiplier;
    
    // 计算需要显示的数字范围（覆盖整个尺子长度）
    // 总长度 = headWidth + 厘米数 * pixelsPerCm
    // 所以最大厘米数 = (totalRulerWidth - headWidth) / pixelsPerCm
    final maxCentimeters = ((totalRulerWidth - headWidth) / pixelsPerCm).ceil();
    
    // 限制显示范围，避免创建过多widget导致滑动卡顿
    // 只显示可见区域附近的数字（前后各3倍屏幕宽度），减少Widget数量提升性能
    final visibleRange = screenWidth * 3;
    int startIndex = 0;
    int endIndex = maxCentimeters;
    
    if (_scrollController.hasClients) {
      final scrollOffset = _scrollController.offset;
      final startCm = ((scrollOffset - visibleRange - headWidth) / pixelsPerCm).floor();
      final endCm = ((scrollOffset + screenWidth + visibleRange - headWidth) / pixelsPerCm).ceil();
      startIndex = startCm.clamp(0, maxCentimeters);
      endIndex = endCm.clamp(0, maxCentimeters);
    } else {
      // 如果滚动控制器未准备好，只显示前200个
      endIndex = maxCentimeters > 200 ? 200 : maxCentimeters;
    }
    
    // markTop已经作为参数传入，直接使用
    
    // 在每个整数厘米位置显示数字（只显示可见区域附近的数字）
    for (int i = startIndex; i <= endIndex; i++) {
      // 计算每个整数厘米对应的像素位置（需要考虑head.png的宽度）
      final xPosition = headWidth + (i * pixelsPerCm);
      
      // 只显示在合理范围内的数字（避免显示在尺子外）
      if (xPosition < -50 || xPosition > totalRulerWidth + 50) {
        continue; // 跳过尺子外的数字
      }
      
      marks.add(
        Positioned(
          left: xPosition,
          top: markTop,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            decoration: BoxDecoration(
              // color: Colors.white.withOpacity(0.9),
              // borderRadius: BorderRadius.circular(2),
              // border: Border.all(color: Colors.black, width: 1),
            ),
            child: Text(
              i.toString(),
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }
    
    return marks;
  }
  
  // 构建鲁班尺刻度标记（根据当前鲁班尺类型的格数绘制）
  List<Widget> _buildLubanScaleMarks(double screenWidth, double screenHeight, double headWidth, double markTop) {
    final List<Widget> marks = [];
    
    // 获取当前鲁班尺类型的格数和每格像素
    final gridCount = _getLubanScaleGridCount();
    final pixelsPerGrid = _xianDaiPixelsPerCentimeter > 0 ? _xianDaiPixelsPerCentimeter : 8.0;
    
    // 确保 pixelsPerGrid 有合理的最小值
    if (pixelsPerGrid < 1.0) {
      return marks;
    }
    
    // 计算整个尺子的总长度（像素）
    final totalRulerWidth = screenWidth * _rulerWidthMultiplier;
    
    // 计算需要显示的数字范围（覆盖整个尺子长度）
    // 每格代表1厘米，所以需要计算能显示多少格
    // 总长度 = headWidth + 格数 * pixelsPerGrid
    // 所以最大格数 = (totalRulerWidth - headWidth) / pixelsPerGrid
    final maxGrids = ((totalRulerWidth - headWidth) / pixelsPerGrid).ceil();
    
    // 限制显示范围，避免创建过多widget导致滑动卡顿
    // 只显示可见区域附近的数字（前后各3倍屏幕宽度），减少Widget数量提升性能
    final visibleRange = screenWidth * 3;
    int startIndex = 0;
    int endIndex = maxGrids;
    
    if (_scrollController.hasClients) {
      final scrollOffset = _scrollController.offset;
      final startGrid = ((scrollOffset - visibleRange - headWidth) / pixelsPerGrid).floor();
      final endGrid = ((scrollOffset + screenWidth + visibleRange - headWidth) / pixelsPerGrid).ceil();
      startIndex = startGrid.clamp(0, maxGrids);
      endIndex = endGrid.clamp(0, maxGrids);
    } else {
      // 如果滚动控制器未准备好，只显示前200格
      endIndex = maxGrids > 200 ? 200 : maxGrids;
    }
    
    // markTop已经作为参数传入，直接使用
    
    // 在每个格的位置显示数字（只显示可见区域附近的数字）
    for (int i = startIndex; i <= endIndex; i++) {
      // 计算每个格对应的像素位置（需要考虑head.png的宽度）
      final xPosition = headWidth + (i * pixelsPerGrid);
      
      // 只显示在合理范围内的数字（避免显示在尺子外）
      if (xPosition < -50 || xPosition > totalRulerWidth + 50) {
        continue; // 跳过尺子外的数字
      }
      
      marks.add(
        Positioned(
          left: xPosition,
          top: markTop,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            decoration: BoxDecoration(
              // color: Colors.white.withOpacity(0.9),
              // borderRadius: BorderRadius.circular(2),
              // border: Border.all(color: Colors.black, width: 1),
            ),
            child: Text(
              i.toString(),
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }
    
    return marks;
  }
  
  // 构建整数厘米标记（用于xiandailubanScale.png）
  List<Widget> _buildCentimeterMarksForXianDai(double screenWidth, double screenHeight, double headWidth, double markTop) {
    final List<Widget> marks = [];
    
    // 使用xiandailubanScale.png的像素到厘米转换比例
    final pixelsPerCm = _xianDaiPixelsPerCentimeter > 0 ? _xianDaiPixelsPerCentimeter : 8.0;
    
    // 确保 pixelsPerCm 有合理的最小值
    if (pixelsPerCm < 1.0) {
      return marks;
    }
    
    // 计算需要显示的数字范围（显示足够多的数字以覆盖整个滚动区域）
    final maxCentimeters = (screenWidth * 5 / pixelsPerCm).ceil();
    
    // 限制显示范围，避免创建过多widget（只显示前500个整数厘米）
    final displayCount = maxCentimeters > 500 ? 500 : maxCentimeters;
    
    // markTop已经作为参数传入，直接使用
    
    // 在每个整数厘米位置显示数字（从0开始）
    for (int i = 0; i <= displayCount; i++) {
      // 计算每个整数厘米对应的像素位置（需要考虑head.png的宽度）
      final xPosition = headWidth + (i * pixelsPerCm);
      
      // 只显示在合理范围内的数字（避免显示在屏幕外）
      if (xPosition < -50 || xPosition > screenWidth * 5 + 50) {
        continue; // 跳过屏幕外的数字
      }
      
      marks.add(
        Positioned(
          left: xPosition,
          top: markTop,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            decoration: BoxDecoration(
              // color: Colors.white.withOpacity(0.9),
              // borderRadius: BorderRadius.circular(2),
              // border: Border.all(color: Colors.black, width: 1),
            ),
            child: Text(
              i.toString(),
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      );
    }
    
    return marks;
  }
  
  @override
  void dispose() {
    // 取消所有定时器
    _initTimer?.cancel();
    _scrollUpdateTimer?.cancel();
    _scrollEndTimer?.cancel();
    // 重置状态
    _isFastScrolling = false;
    _lastScrollTime = null;
    // 释放ValueNotifier
    _currentCentimetersNotifier.dispose();
    _lubanFortuneNotifier.dispose();
    _dinglanFortuneNotifier.dispose();
    // 释放输入框控制器
    _centimetersInputController.dispose();
    // 移除滚动监听器
    _scrollController.removeListener(_onScroll);
    // 释放滚动控制器
    _scrollController.dispose();
    // 不再在 dispose 中恢复屏幕方向，改为在返回时提前恢复
    // 这样可以避免关闭动画和方向切换冲突导致的卡顿
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    final orientation = MediaQuery.of(context).orientation;
    
    // 检测屏幕方向或尺寸变化
    final bool orientationChanged = _currentOrientation != null && _currentOrientation != orientation;
    final bool sizeChanged = _lastScreenSize != null && 
        (_lastScreenSize!.width != screenSize.width || _lastScreenSize!.height != screenSize.height);
    
    if (orientationChanged || sizeChanged) {
      // 方向或尺寸已改变，重置初始化标志，等待旋转完成后再计算
      _isInitialized = false;
      _currentCentimetersNotifier.value = 0.0;
      _updateFortuneInfo(0.0);
      _pixelsPerCentimeter = 8.0;
      _xianDaiPixelsPerCentimeter = 8.0;
      _headWidth = 0.0;
      _rulerDisplayHeight = 0.0;
      // 取消之前的定时器
      _initTimer?.cancel();
    }
    _currentOrientation = orientation;
    _lastScreenSize = screenSize;
    
    // 使用 PopScope 来监听返回事件，提前恢复屏幕方向
    // 在页面开始返回时立即恢复屏幕方向，使用微任务确保在当前事件循环结束时执行
    // 这样可以避免影响返回动画，同时让屏幕方向在页面完全关闭前就开始恢复
    return PopScope(
      canPop: true,
      onPopInvoked: (bool didPop) {
        if (didPop) {
          // 立即恢复屏幕方向，使用 Future.microtask 在当前事件循环结束时执行
          // 这样可以确保在返回动画开始之前就恢复方向，避免卡顿
          Future.microtask(() {
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]);
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
          });
        }
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 使用LayoutBuilder获取实际的布局尺寸，确保布局完成
          final layoutWidth = constraints.maxWidth;
          final layoutHeight = constraints.maxHeight;
          final isLandscape = layoutWidth > layoutHeight;
        
        // 初始化尺子比例（在build中调用，确保context可用）
        // 等待屏幕旋转完成后再计算
        if (!_isInitialized && isLandscape && layoutWidth > 0 && layoutHeight > 0) {
          // 取消之前的定时器
          _initTimer?.cancel();
          
          // 先等待当前帧完成
          WidgetsBinding.instance.addPostFrameCallback((_) {
            // 再延迟一段时间，确保屏幕旋转和布局都完成
            _initTimer = Timer(const Duration(milliseconds: 500), () {
              if (mounted && !_isInitialized) {
                // 再次获取最新的布局尺寸和方向
                final currentConstraints = constraints;
                final currentOrientation = MediaQuery.of(context).orientation;
                
                // 确保是横屏且布局尺寸有效
                if (currentOrientation == Orientation.landscape &&
                    currentConstraints.maxWidth > currentConstraints.maxHeight &&
                    currentConstraints.maxWidth > 0 &&
                    currentConstraints.maxHeight > 0) {
                  _initializeRulerScale(currentConstraints.maxHeight);
                }
              }
            });
          });
        }
    
        return Scaffold(
          body: GestureDetector(
            // 点击屏幕任意位置时，隐藏系统UI（如果已显示）
            onTap: () {
              // 重新设置沉浸式模式，隐藏系统UI
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
            },
            behavior: HitTestBehavior.translucent,
            child: Stack(
              children: [
                // 2. 页面背景图
                Positioned.fill(
                  child: AppAssetImage(
                    assetPath: 'assets/luban/background.png',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(color: const Color(0xFFF5F5F5));
                    },
                  ),
                ),
                // 主要内容
                // 使用 SafeArea 来考虑系统UI占用的空间，避免内容被遮挡
                SafeArea(
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          // 尺子区域（占据剩余高度，避免与控制面板叠加溢出）
                          Expanded(
                            child: Padding(
                            padding: const EdgeInsets.only(top: 20, left: 20),
                            child: LayoutBuilder(
                              builder: (context, rulerBox) {
                                return Align(
                                  alignment: Alignment.topLeft,
                                  child: SingleChildScrollView(
                            controller: _scrollController,
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.zero,
                            physics: const _EnhancedInertialScrollPhysics(), // 使用增强惯性滚动物理效果
                            child: FutureBuilder<List<Size>>(
                              key: ValueKey(_lubanType),
                              future: Future.wait([
                                _getImageSize(_getScaleImagePath()),
                                _getImageSize(_getFortuneImagePath()),
                                _getImageSize('assets/luban/dinglan.png'),
                                _getImageSize('assets/luban/dingLanScale.png'),
                                _getImageSize('assets/luban/head.png'),
                              ]),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData || snapshot.data == null) {
                                  return const SizedBox.shrink();
                                }

                                final lubanScaleH =
                                    _scaledImageHeight(snapshot.data![0]);
                                final fortuneH =
                                    _scaledImageHeight(snapshot.data![1]);
                                final dinglanH =
                                    _scaledImageHeight(snapshot.data![2]);
                                final dingLanScaleH =
                                    _scaledImageHeight(snapshot.data![3]);
                                final headSize = snapshot.data![4];
                                final contentHeight = _computeRulerContentHeight(
                                  lubanScaleH,
                                  fortuneH,
                                  dinglanH,
                                  dingLanScaleH,
                                );
                                _syncRulerDisplayHeight(contentHeight);

                                final rulerWidth =
                                    screenWidth * _rulerWidthMultiplier;
                                double headWidth = 100;
                                if (headSize.height > 0 && contentHeight > 0) {
                                  headWidth = _scaledImageWidth(
                                    headSize,
                                    contentHeight,
                                  );
                                }
                                if (headWidth <= 0) {
                                  headWidth =
                                      _headWidth > 0 ? _headWidth : 100;
                                }

                                final fortuneTop = lubanScaleH;
                                final dinglanTop = lubanScaleH + fortuneH;
                                final dingLanScaleTop =
                                    contentHeight - dingLanScaleH;
                                final pixelsPerCm = _pixelsPerCentimeter > 0
                                    ? _pixelsPerCentimeter
                                    : 8.0;

                                return SizedBox(
                                  width: rulerWidth,
                                  height: contentHeight,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      // 底图与 head：高度压缩为各层叠加总高
                                      Positioned(
                                        top: 0,
                                        left: 0,
                                        child: Container(
                                          width: rulerWidth,
                                          height: contentHeight,
                                          decoration: BoxDecoration(
                                            image: DecorationImage(
                                              image: appAssetImageProvider(
                                                'assets/luban/rulerBaseDrawing.png',
                                              ),
                                              repeat: ImageRepeat.repeatX,
                                              fit: BoxFit.fitHeight,
                                              alignment: Alignment.topLeft,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        top: 0,
                                        left: 0,
                                        child: SizedBox(
                                          height: contentHeight,
                                          child: AppAssetImage(
                                            assetPath: 'assets/luban/head.png',
                                            fit: BoxFit.fitHeight,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                              return const SizedBox.shrink();
                                            },
                                          ),
                                        ),
                                      ),
                                      // 顶部鲁班尺刻度
                                      Positioned(
                                        top: 0,
                                        left: 0,
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _transparentHeadSpacer(contentHeight),
                                            Container(
                                              width: rulerWidth,
                                              height: lubanScaleH,
                                              decoration: BoxDecoration(
                                                image: DecorationImage(
                                                  image: appAssetImageProvider(
                                                    _getScaleImagePath(),
                                                  ),
                                                  repeat: ImageRepeat.repeatX,
                                                  fit: BoxFit.fitHeight,
                                                  alignment: Alignment.topLeft,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // 吉凶图（下边与 dinglan 上边重合）
                                      Positioned(
                                        top: fortuneTop,
                                        left: 0,
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _transparentHeadSpacer(contentHeight),
                                            Container(
                                              width: rulerWidth,
                                              height: fortuneH,
                                              decoration: BoxDecoration(
                                                image: DecorationImage(
                                                  image: appAssetImageProvider(
                                                    _getFortuneImagePath(),
                                                  ),
                                                  repeat: ImageRepeat.repeatX,
                                                  fit: BoxFit.fitHeight,
                                                  alignment: Alignment.topLeft,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // 丁兰文字图（紧贴吉凶图下方）
                                      Positioned(
                                        top: dinglanTop,
                                        left: 0,
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _transparentHeadSpacer(contentHeight),
                                            Container(
                                              width: rulerWidth,
                                              height: dinglanH,
                                              decoration: BoxDecoration(
                                                image: DecorationImage(
                                                  image: appAssetImageProvider(
                                                    'assets/luban/dinglan.png',
                                                  ),
                                                  repeat: ImageRepeat.repeatX,
                                                  fit: BoxFit.fitHeight,
                                                  alignment: Alignment.topLeft,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // 底部丁兰刻度
                                      Positioned(
                                        top: dingLanScaleTop,
                                        left: 0,
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _transparentHeadSpacer(contentHeight),
                                            Container(
                                              width: rulerWidth,
                                              height: dingLanScaleH,
                                              decoration: BoxDecoration(
                                                image: DecorationImage(
                                                  image: appAssetImageProvider(
                                                    'assets/luban/dingLanScale.png',
                                                  ),
                                                  repeat: ImageRepeat.repeatX,
                                                  fit: BoxFit.fitHeight,
                                                  alignment: Alignment.topLeft,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      ..._buildLubanScaleMarks(
                                        screenWidth,
                                        screenHeight,
                                        headWidth,
                                        lubanScaleH / 2 - 10,
                                      ),
                                      ..._buildCentimeterMarks(
                                        screenWidth,
                                        screenHeight,
                                        headWidth,
                                        pixelsPerCm,
                                        dingLanScaleTop + dingLanScaleH / 2 - 10,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      // 下半部分：控制面板
                      // 动态计算底部padding，考虑系统UI的高度，避免溢出
                      Padding(
                        padding: EdgeInsets.only(
                          left: 20,
                          right: 20,
                          top: 12,
                          bottom: _calculateBottomPadding(context, isLandscape),
                        ),
                        child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                          // 左侧：输入框和箭头按钮
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 鲁班尺类型切换按钮
                                GestureDetector(
                                  onTap: () => _showLubanTypeSelector(context),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.8),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '$_lubanType切换',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.black,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ValueListenableBuilder<double>(
                                  valueListenable: _currentCentimetersNotifier,
                                  builder: (context, cm, child) =>
                                      _buildDualUnitLabels(cm),
                                ),
                                const SizedBox(height: 6),
                                // 输入框和箭头
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.arrow_back_ios,
                                        color: Colors.black,
                                        size: 18,
                                      ),
                                      onPressed: () => _adjustCentimeters(-0.1),
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.white.withOpacity(0.8),
                                        minimumSize: const Size(36, 36),
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 148,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFD4B896),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: Colors.black.withOpacity(0.15),
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: ValueListenableBuilder<double>(
                                              valueListenable:
                                                  _currentCentimetersNotifier,
                                              builder: (context, value, child) {
                                                return GestureDetector(
                                                  onTap: () =>
                                                      _showCentimetersInputSheet(
                                                          context),
                                                  child: Align(
                                                    alignment: Alignment.center,
                                                    child: Text(
                                                      _formatDisplayValue(value),
                                                      style: const TextStyle(
                                                        fontSize: 20,
                                                        color: Colors.black,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: _toggleDisplayUnit,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.black,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                _primaryUnitLabel,
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.arrow_forward_ios,
                                        color: Colors.black,
                                        size: 18,
                                      ),
                                      onPressed: () => _adjustCentimeters(0.1),
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.white.withOpacity(0.8),
                                        minimumSize: const Size(36, 36),
                                        padding: EdgeInsets.zero,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                ],
              ),
            ),
                          const SizedBox(width: 20),
                          // 右侧：鲁班和丁兰信息框
                          Container(
                            width: 120,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.black, width: 2),
                              color: Colors.white.withOpacity(0.9),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 鲁班信息
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(color: Colors.black, width: 1),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '魯班:',
        style: TextStyle(
                                          fontSize: 12,
          color: Colors.black,
                                        ),
                                      ),
                                      ValueListenableBuilder<String>(
                                        valueListenable: _lubanFortuneNotifier,
                                        builder: (context, value, child) {
                                          return Text(
                                            value,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              color: Colors.red,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                // 丁兰信息
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '丁蘭:',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.black,
                                        ),
                                      ),
                                      ValueListenableBuilder<String>(
                                        valueListenable: _dinglanFortuneNotifier,
                                        builder: (context, value, child) {
                                          return Text(
                                            value,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              color: Colors.red,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                        ], // Column children 结束
                      ), // Column 结束
                    // biaochi.png（固定位置，红线初始对齐 head.png 右缘）
                    Positioned(
                  top: 20, // 与尺子区域的顶部对齐（考虑padding）
                  left: 20, // 与尺子区域的左边对齐（考虑padding）
                  child: FutureBuilder<List<Size>>(
                    future: Future.wait([
                      _getImageSize('assets/luban/head.png'),
                      _getImageSize('assets/luban/biaochi.png'),
                    ]),
                    builder: (context, snapshot) {
                      final double headHeight = _rulerDisplayHeight > 0
                          ? _rulerDisplayHeight
                          : _rulerOverlayHeight(
                              context,
                              layoutHeight,
                              isLandscape,
                            );
                      double headWidth = 100;
                      Size biaochiSize = Size.zero;

                      if (snapshot.hasData) {
                        final headSize = snapshot.data![0];
                        biaochiSize = snapshot.data![1];
                        headWidth = _scaledImageWidth(headSize, headHeight);
                        if (headWidth <= 0) headWidth = 100;
                      }

                      final biaochiOffsetX = biaochiSize.height > 0
                          ? _biaochiTranslateXAtHeadRightEdge(
                              headHeight,
                              biaochiSize,
                            )
                          : 0.0;

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: headWidth,
                            height: headHeight,
                          ),
                          Transform.translate(
                            offset: Offset(biaochiOffsetX, 0),
                            child: SizedBox(
                              height: headHeight,
                              child: AppAssetImage(
                                assetPath: 'assets/luban/biaochi.png',
                                fit: BoxFit.fitHeight,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 50,
                                    height: headHeight,
                                    color: Colors.red.withOpacity(0.5),
                                    child: const Center(
                                      child: Text('biaochi\n加载失败'),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                // 左上角返回按钮
                Positioned(
                  top: 0,
                  left: 0,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.3),
                    ),
                  ),
                ),
                ], // SafeArea 内的 Stack 的 children 结束
              ), // SafeArea 内的 Stack 结束
            ), // SafeArea 结束
          ], // GestureDetector 的 Stack 的 children 结束（包含背景图和 SafeArea）
        ), // GestureDetector 的 Stack 结束
      ), // GestureDetector 的 child 结束（Stack）
    ); // Scaffold 的 body 结束（GestureDetector）
        }, // LayoutBuilder 的 builder 闭包结束
      ), // LayoutBuilder 结束（PopScope 的 child 参数）
    ); // PopScope 结束，return 语句结束
  }
}

// 自定义增强惯性滚动物理效果
// 使用 ClampingScrollPhysics 作为基础，避免边界反弹影响惯性效果
class _EnhancedInertialScrollPhysics extends ClampingScrollPhysics {
  const _EnhancedInertialScrollPhysics({super.parent});

  @override
  _EnhancedInertialScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _EnhancedInertialScrollPhysics(parent: buildParent(ancestor));
  }

  // 进一步减小摩擦系数，让滑动更流畅，惯性更明显且持续时间更长
  // 使用非常小的摩擦系数，确保惯性持续时间足够长
  @override
  double get friction => 0.001;

  // 大幅降低最小滑动速度阈值，让几乎所有滑动都能触发惯性
  // 降低到3，确保即使非常轻微的滑动也能产生惯性
  @override
  double get minFlingVelocity => 3.0;

  // 增加最大滑动速度，支持快速滑动
  @override
  double get maxFlingVelocity => 15000.0;

  // 调整速度容差，让惯性滚动更敏感，确保模拟持续运行
  @override
  Tolerance get tolerance => const Tolerance(
    velocity: 0.000001,
    distance: 0.000001,
  );

  // 创建惯性滚动模拟，确保总是创建模拟以产生惯性效果
  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    // 如果速度为零或接近零，不创建模拟（避免不必要的滚动）
    if (velocity.abs() < 0.01) {
      return null;
    }
    
    // 对于所有速度都进行增强，确保惯性效果明显且稳定
    double adjustedVelocity = velocity;
    
    // 根据速度大小，使用更激进的增强倍数，确保惯性持续时间足够长
    if (velocity.abs() < 20.0) {
      // 如果速度很小（< 20），放大5倍以确保明显的惯性
      adjustedVelocity = velocity * 5.0;
    } else if (velocity.abs() < 50.0) {
      // 如果速度较小（20-50），放大3.5倍
      adjustedVelocity = velocity * 3.5;
    } else if (velocity.abs() < 100.0) {
      // 如果速度中等（50-100），放大2.5倍
      adjustedVelocity = velocity * 2.5;
    } else if (velocity.abs() < 200.0) {
      // 如果速度较大（100-200），放大2倍
      adjustedVelocity = velocity * 2.0;
    } else if (velocity.abs() < 400.0) {
      // 如果速度很大（200-400），放大1.5倍
      adjustedVelocity = velocity * 1.5;
    } else if (velocity.abs() < 800.0) {
      // 如果速度非常大（400-800），放大1.2倍
      adjustedVelocity = velocity * 1.2;
    }
    // 速度大于800时，保持原速度

    // 确保调整后的速度至少达到最小阈值，保证有足够的惯性
    if (adjustedVelocity.abs() < minFlingVelocity) {
      // 如果调整后仍然太小，至少设置为最小阈值的4倍，确保有明显的惯性
      adjustedVelocity = adjustedVelocity.sign * minFlingVelocity * 4.0;
    }

    // 使用父类方法创建模拟，使用调整后的速度
    // ClampingScrollPhysics 的 createBallisticSimulation 会在边界处停止
    final simulation = super.createBallisticSimulation(position, adjustedVelocity);
    
    // 如果父类返回null（不应该发生，但为了安全），创建一个模拟
    if (simulation == null && adjustedVelocity.abs() >= minFlingVelocity) {
      return ClampingScrollSimulation(
        position: position.pixels,
        velocity: adjustedVelocity,
        friction: friction,
        tolerance: tolerance,
      );
    }
    
    return simulation;
  }
}

