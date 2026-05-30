import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'api_config.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'main.dart';
import 'style_preference_api.dart';
class CompassPage extends StatefulWidget {
  final String compassDialImage;
  
  const CompassPage({
    super.key,
    this.compassDialImage = 'assets/compass/black.png',
  });

  @override
  State<CompassPage> createState() => _CompassPageState();
}

class _CompassPageState extends State<CompassPage> with SingleTickerProviderStateMixin {
  late String _currentDialImage;
  double _heading = 0.0;
  double? _latitude;
  double? _longitude;
  double? _altitude;
  double? _pressure;
  double? _magneticForce;
  StreamSubscription<Position>? _positionSubscription;
  
  StreamSubscription<CompassEvent>? _compassSubscription;
  StreamSubscription<MagnetometerEvent>? _magnetometerSubscription;
  late AnimationController _animationController;
  double _targetHeading = 0.0;
  double _currentHeading = 0.0;
  final List<double> _headingHistory = []; // 用于平滑处理的历史数据
  static const int _historySize = 5; // 历史数据大小

  @override
  void initState() {
    super.initState();
    _currentDialImage = widget.compassDialImage;
    _loadSavedDial();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16), // 约60fps
    )..repeat();
    
    _animationController.addListener(() {
      if (mounted) {
        setState(() {
          // 平滑过渡到目标角度，使用更小的步进值
          double diff = _targetHeading - _currentHeading;
          if (diff > 180) {
            diff -= 360;
          } else if (diff < -180) {
            diff += 360;
          }
          // 使用更平滑的插值，根据差值大小调整步进
          double step = diff.abs() > 5 ? 0.25 : 0.1; // 大角度变化时更快，小角度时更平滑
          _currentHeading += diff * step;
          if (_currentHeading < 0) {
            _currentHeading += 360;
          } else if (_currentHeading >= 360) {
            _currentHeading -= 360;
          }
        });
      }
    });
    
    _startCompass();
    _startMagnetometer();
    _getLocation();
    _startLocationStream();
  }
  
  @override
  void didUpdateWidget(CompassPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.compassDialImage != widget.compassDialImage) {
      setState(() {
        _currentDialImage = widget.compassDialImage;
      });
    }
  }

  /// 从后端加载当前用户在指南针页面选择过的表盘样式
  Future<void> _loadSavedDial() async {
    final prefs = await StylePreferenceApi.loadPreferences('compassDial');
    final dial = prefs['compassDial'];
    if (dial != null && dial.isNotEmpty && mounted) {
      setState(() {
        _currentDialImage = dial;
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    _compassSubscription?.cancel();
    _magnetometerSubscription?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }

  void _startCompass() {
    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (event.heading != null) {
        double heading = event.heading!;
        if (heading < 0) {
          heading = heading + 360;
        }
        heading = heading % 360;
        
        // 使用移动平均平滑处理
        _headingHistory.add(heading);
        if (_headingHistory.length > _historySize) {
          _headingHistory.removeAt(0);
        }
        
        // 计算平均值，处理角度跨越0/360的情况
        double sum = 0.0;
        for (int i = 0; i < _headingHistory.length; i++) {
          double h = _headingHistory[i];
          // 相对于第一个值进行归一化
          if (i > 0) {
            double diff = h - _headingHistory[0];
            if (diff > 180) {
              h -= 360;
            } else if (diff < -180) {
              h += 360;
            }
          }
          sum += h;
        }
        double smoothedHeading = sum / _headingHistory.length;
        
        // 归一化到0-360范围
        if (smoothedHeading < 0) {
          smoothedHeading += 360;
        } else if (smoothedHeading >= 360) {
          smoothedHeading -= 360;
        }
        
        if (mounted) {
          setState(() {
            _targetHeading = smoothedHeading;
            _heading = smoothedHeading;
          });
        }
      }
    });
  }

  void _startMagnetometer() {
    _magnetometerSubscription = magnetometerEventStream().listen((event) {
      // 计算磁场强度（微特斯拉）
      // 磁场强度 = sqrt(x^2 + y^2 + z^2)
      double magnitude = sqrt(
        event.x * event.x + 
        event.y * event.y + 
        event.z * event.z
      );
      
      if (mounted) {
        setState(() {
          _magneticForce = magnitude;
        });
      }
    });
  }

  void _startLocationStream() {
    // 持续更新定位/海拔，避免一次性 getCurrentPosition 拿到 0.0 后长期不变
    const settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 5,
    );

    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen((position) {
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;

        // 有些设备/场景下 altitude 会返回 0.0 但并不可靠；优先用 altitudeAccuracy 判断可用性
        final altAcc = position.altitudeAccuracy;
        if (altAcc != null && altAcc > 0) {
          _altitude = position.altitude;
        } else {
          // 若没有可用的海拔精度信息，则保留上一次有效值（不强行覆盖为 0.0）
          if (_altitude == null && position.altitude != 0.0) {
            _altitude = position.altitude;
          }
        }
      });
    });
  }

  Future<void> _getLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          final altAcc = position.altitudeAccuracy;
          if (altAcc != null && altAcc > 0) {
            _altitude = position.altitude;
          } else {
            // 不用不可靠的 0.0 覆盖 UI
            _altitude = position.altitude == 0.0 ? _altitude : position.altitude;
          }
        });
      }
    } catch (e) {
      print('获取位置失败: $e');
    }
  }

  String _getDirection(double heading) {
    const directions = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
    int index = ((heading + 22.5) / 45).floor() % 8;
    return directions[index];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部栏
            _buildTopBar(),
            
            // 方向显示
            _buildDirectionDisplay(),
            
            // 指南针
            Expanded(
              child: Center(
                child: _buildCompass(),
              ),
            ),
            
            // 底部数据框
            _buildBottomData(),
            
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
            },
            child: const HomeToolbarIcon(
              assetPath: 'assets/home/luopan.png',
              size: 40,
              fallbackIcon: Icons.explore,
              fallbackIconSize: 28,
            ),
          ),
          PopupMenuButton<String>(
            offset: const Offset(0, 5), // 从按钮下方弹出
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 8,
            color: Colors.white,
            onSelected: (String value) {
              if (value == '样式') {
                // 点击样式后跳转到选择罗盘页面
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CompassHomePage(
                      compassDialOnly: true,
                      onBack: () {
                        Navigator.pop(context);
                      },
                      onCompassDialSelected: (String dialImage) {
                        // 先关闭样式页面
                        Navigator.pop(context);
                        // 然后更新当前指南针页面的表盘图片
                        setState(() {
                          _currentDialImage = dialImage;
                        });
                        // 持久化指南针表盘样式
                        StylePreferenceApi.savePreference(
                          page: 'compassDial',
                          prefKey: 'compassDial',
                          prefValue: dialImage,
                        );
                      },
                    ),
                  ),
                );
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
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
            ],
            child: const HomeToolbarIcon(
              assetPath: 'assets/home/menu.png',
              size: 40,
              fallbackIcon: Icons.menu,
              fallbackIconSize: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectionDisplay() {
    final direction = _getDirection(_heading);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: [
          Text(
            '$direction ${_heading.toStringAsFixed(1)}°',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '经度: ${_longitude?.toStringAsFixed(1) ?? '0'}°',
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(width: 20),
              Text(
                '纬度: ${_latitude?.toStringAsFixed(1) ?? '0'}°',
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompass() {
    final screenSize = MediaQuery.of(context).size;
    final compassSize = min(screenSize.width, screenSize.height) * 0.8;
    
    return Stack(
      alignment: Alignment.center,
      children: [
        // 指南针背景
        Transform.rotate(
          angle: -_currentHeading * pi / 180 + pi, // 初始旋转180度
          child: AppAssetImage(
            assetPath: _currentDialImage,
            width: compassSize,
            height: compassSize,
            fit: BoxFit.contain,
          ),
        ),
        // 指针（不旋转，始终指向北方）
        AppAssetImage(
          assetPath: 'assets/compass/zhizhen.png',
          width: compassSize * 0.9,
          height: compassSize * 0.9,
          fit: BoxFit.contain,
        ),
      ],
    );
  }

  Widget _buildBottomData() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildDataBox(
            '海拔',
            _altitude != null ? '${_altitude!.toStringAsFixed(1)}m' : '--',
          ),
          _buildDataBox('大气压', _pressure?.toStringAsFixed(1) ?? '30.1'),
          _buildDataBox('磁力', _magneticForce?.toStringAsFixed(1) ?? '30.1'),
        ],
      ),
    );
  }

  Widget _buildDataBox(String label, String value) {
    return Container(
      width: 100,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

/// 顶栏 PNG 图标（素材为浅色/白色），叠色为 [color] 以便在白底上可见。
class HomeToolbarIcon extends StatelessWidget {
  const HomeToolbarIcon({
    super.key,
    required this.assetPath,
    this.size = 36,
    this.color = Colors.black,
    this.fit = BoxFit.contain,
    this.fallbackIcon,
    this.fallbackIconSize,
  });

  final String assetPath;
  final double size;
  final Color color;
  final BoxFit fit;
  final IconData? fallbackIcon;
  final double? fallbackIconSize;

  @override
  Widget build(BuildContext context) {
    final iconSize = fallbackIconSize ?? size * 0.65;
    return SizedBox(
      width: size,
      height: size,
      child: ColorFiltered(
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        child: AppAssetImage(
          assetPath: assetPath,
          fit: fit,
          errorBuilder: (_, __, ___) => Icon(
            fallbackIcon ?? Icons.image_not_supported_outlined,
            size: iconSize,
            color: color,
          ),
        ),
      ),
    );
  }
}
