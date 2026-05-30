import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'api_config.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'tianditu.dart';
import 'utils/asset_rotation.dart';

class MapCompassPage extends StatefulWidget {
  const MapCompassPage({super.key});

  @override
  State<MapCompassPage> createState() => _MapCompassPageState();
}

class _MapCompassPageState extends State<MapCompassPage> with SingleTickerProviderStateMixin {
  double _heading = 0.0; // 指南针方向（度）
  double? _latitude;
  double? _longitude;
  double? _altitude;
  double? _pressure; // 气压（hPa）
  double? _seaLevelPressure; // 海平面气压（hPa）
  String? _address;
  bool _isLoading = true;
  bool _isLoadingLocation = false;
  bool _isLoadingAltitude = false;
  
  StreamSubscription<CompassEvent>? _compassSubscription;
  late AnimationController _animationController;
  double _targetHeading = 0.0;
  double _currentHeading = 0.0;
  
  final MapController _mapController = MapController();
  bool _isMapReady = false;
  String _compassImagePath = 'assets/gold/0-SimplePlate-BaguaTwentyFour.png';
  
  // 罗盘位置和缩放
  double _compassOffsetY = 0.0; // 垂直偏移量
  double _compassOffsetX = 0.0; // 水平偏移量
  double _compassScale = 1.0; // 缩放比例，最小为0.3（30%），但会自动回弹到1.0
  double _initialScale = 1.0; // 缩放开始时的初始值
  bool _isScaling = false; // 是否正在缩放
  bool _isDragging = false; // 是否正在拖动（垂直或水平）
  
  // 罗盘透明度设置
  double _compassOpacity = 1.0; // 罗盘透明度，范围 0.0-1.0
  bool _useBlackLine = false; // 是否使用黑线条（true=黑线条，false=白线条），默认白线条
  
  // 锁定功能
  bool _isLocked = false; // 是否锁定
  double _lockedHeading = 0.0; // 锁定时的角度
  double _compassRotationOffset = 0.0; // 罗盘旋转偏移角度（度）
  bool _showRotationPanel = false; // 是否显示旋转调整面板
  
  // 地图类型
  bool _isSatelliteMap = false; // 是否为卫星地图（true=卫星，false=普通）

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _searchDebounce;
  List<TiandituSearchSuggestion> _searchSuggestions = [];
  bool _isSearchSuggesting = false;
  bool _showSearchSuggestions = false;
  int _searchRequestId = 0;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..repeat();
    
    _animationController.addListener(() {
      if (mounted) {
        setState(() {
          double diff = _targetHeading - _currentHeading;
          if (diff > 180) {
            diff -= 360;
          } else if (diff < -180) {
            diff += 360;
          }
          double step = diff.abs() > 5 ? 0.25 : 0.1;
          _currentHeading += diff * step;
          if (_currentHeading < 0) {
            _currentHeading += 360;
          } else if (_currentHeading >= 360) {
            _currentHeading -= 360;
          }
        });
      }
    });
    
    _searchFocus.addListener(_onSearchFocusChanged);
    _startCompass();
    _getLocation();
  }

  void _onSearchFocusChanged() {
    if (!_searchFocus.hasFocus) {
      if (mounted) {
        setState(() => _showSearchSuggestions = false);
      }
      return;
    }
    final q = _searchController.text.trim();
    if (q.isEmpty || !mounted) return;
    if (_searchSuggestions.isNotEmpty) {
      setState(() => _showSearchSuggestions = true);
    } else {
      _fetchSearchSuggestions(q);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    _animationController.dispose();
    _compassSubscription?.cancel();
    _mapController.dispose();
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
        
        if (mounted) {
          setState(() {
            _targetHeading = heading;
            _heading = heading;
          });
        }
      }
    });
  }

  Future<void> _getLocation() async {
    setState(() {
      _isLoading = true;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请启用位置服务')),
          );
        }
        setState(() {
          _isLoading = false;
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
            _isLoading = false;
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
          _isLoading = false;
        });
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _altitude = position.altitude;
          _isLoading = false;
        });
        
        // 如果地图已准备好，移动地图到当前位置
        if (_isMapReady && _latitude != null && _longitude != null) {
          try {
            _mapController.move(
              LatLng(_latitude!, _longitude!),
              15.0,
            );
          } catch (e) {
            print('移动地图失败: $e');
          }
        }
        
        // 获取地址信息
        _getAddressFromCoordinates(position.latitude, position.longitude);
      }
    } catch (e) {
      print('获取位置失败: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取位置失败: $e')),
        );
      }
    }
  }

  Future<void> _getAddressFromCoordinates(double latitude, double longitude) async {
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
        
        if (mounted) {
          setState(() {
            _address = address.isNotEmpty ? address : '未知位置';
          });
        }
      }
    } catch (e) {
      print('获取地址失败: $e');
      if (mounted) {
        setState(() {
          _address = '获取失败';
        });
      }
    }
  }

  Future<void> _fetchSearchSuggestions(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) {
      if (mounted) {
        setState(() {
          _searchSuggestions = [];
          _isSearchSuggesting = false;
          _showSearchSuggestions = false;
        });
      }
      return;
    }

    final requestId = ++_searchRequestId;
    if (mounted) {
      setState(() {
        _isSearchSuggesting = true;
        _showSearchSuggestions = _searchFocus.hasFocus;
      });
    }

    try {
      final bound = (_longitude != null && _latitude != null)
          ? TiandituSearch.mapBoundAround(_longitude!, _latitude!)
          : null;
      final suggestions = await TiandituSearch.suggest(q, mapBound: bound);
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _searchSuggestions = suggestions;
        _isSearchSuggesting = false;
        _showSearchSuggestions =
            _searchFocus.hasFocus && suggestions.isNotEmpty;
      });
    } catch (_) {
      if (!mounted || requestId != _searchRequestId) return;
      setState(() {
        _searchSuggestions = [];
        _isSearchSuggesting = false;
        _showSearchSuggestions = false;
      });
    }
  }

  void _clearSearch() {
    _searchRequestId++;
    _searchDebounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchSuggestions = [];
      _isSearchSuggesting = false;
      _showSearchSuggestions = false;
    });
  }

  Future<void> _moveToCoordinates(double lat, double lon, {String? address}) async {
    if (mounted) {
      setState(() {
        _latitude = lat;
        _longitude = lon;
        _isLoading = false;
        if (address != null && address.isNotEmpty) {
          _address = address;
        }
      });
    }
    if (_isMapReady) {
      _mapController.move(LatLng(lat, lon), 15.0);
    }
    if (address == null || address.isEmpty) {
      await _getAddressFromCoordinates(lat, lon);
    }
  }

  Future<void> _onSelectSuggestion(TiandituSearchSuggestion item) async {
    _searchController.text = item.name;
    _searchFocus.unfocus();
    if (mounted) {
      setState(() {
        _showSearchSuggestions = false;
        _searchSuggestions = [];
      });
    }
    final addr = item.address.isNotEmpty ? item.address : item.name;
    await _moveToCoordinates(item.latitude, item.longitude, address: addr);
  }

  Future<void> _searchAndMove(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return;

    final cachedSuggestions = List<TiandituSearchSuggestion>.from(_searchSuggestions);
    _searchFocus.unfocus();
    if (mounted) {
      setState(() {
        _showSearchSuggestions = false;
        _searchSuggestions = [];
      });
    }

    if (cachedSuggestions.isNotEmpty) {
      final first = cachedSuggestions.first;
      if (first.name == q || first.displayText.startsWith(q)) {
        await _onSelectSuggestion(first);
        return;
      }
    }

    try {
      final bound = (_longitude != null && _latitude != null)
          ? TiandituSearch.mapBoundAround(_longitude!, _latitude!)
          : null;
      final suggestions = await TiandituSearch.suggest(q, mapBound: bound);
      if (suggestions.isNotEmpty) {
        await _onSelectSuggestion(suggestions.first);
        return;
      }

      final locations = await locationFromAddress(q);
      if (locations.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('未找到该地址')),
          );
        }
        return;
      }
      final loc = locations.first;
      await _moveToCoordinates(loc.latitude, loc.longitude);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('搜索失败: $e')),
        );
      }
    }
  }

  Widget _buildSearchBar() {
    return Container(
      height: 40,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '请输入搜索地址',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          prefixIcon: const Icon(Icons.search, color: Colors.white, size: 22),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.white, size: 20),
                  onPressed: _clearSearch,
                ),
        ),
        onChanged: (value) {
          setState(() {});
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 300), () {
            _fetchSearchSuggestions(value);
          });
        },
        onSubmitted: _searchAndMove,
      ),
    );
  }

  Widget _buildSearchSuggestionsPanel() {
    final maxHeight = MediaQuery.of(context).size.height * 0.45;
    return Material(
      color: Colors.white,
      elevation: 2,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: _isSearchSuggesting && _searchSuggestions.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _searchSuggestions.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  thickness: 0.5,
                  color: Colors.grey[300],
                ),
                itemBuilder: (context, index) {
                  final item = _searchSuggestions[index];
                  return InkWell(
                    onTap: () => _onSelectSuggestion(item),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Text(
                        item.displayText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  String _getDirection(double heading) {
    const directions = ['北', '东北', '东', '东南', '南', '西南', '西', '西北'];
    int index = ((heading + 22.5) / 45).floor() % 8;
    return directions[index];
  }

  String _getSittingDirection(double heading) => mountainAt(heading);

  String _getOppositeSittingDirection(double heading) =>
      oppositeMountainAt(heading);

  // 格式化坐标（度分秒）
  String _formatCoordinate(double coordinate, bool isLatitude) {
    int degrees = coordinate.abs().floor();
    double minutesDecimal = (coordinate.abs() - degrees) * 60;
    int minutes = minutesDecimal.floor();
    double seconds = (minutesDecimal - minutes) * 60;

    return '${degrees}°${minutes}′${seconds.toStringAsFixed(0)}″';
  }
  
  // 动画回弹到指定缩放值
  void _animateScaleTo(double targetScale) {
    final startScale = _compassScale;
    final endScale = targetScale;
    final duration = const Duration(milliseconds: 300);
    final startTime = DateTime.now();
    
    // 使用定时器实现动画
    Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      final elapsed = DateTime.now().difference(startTime);
      if (elapsed >= duration) {
        setState(() {
          _compassScale = endScale;
          _compassOffsetX = 0.0;
        });
        timer.cancel();
        return;
      }
      
      final progress = elapsed.inMilliseconds / duration.inMilliseconds;
      final curveValue = Curves.easeOut.transform(progress);
      final currentScale = startScale + (endScale - startScale) * curveValue;
      
      setState(() {
        _compassScale = currentScale;
        // 回弹时重置水平偏移
        if (_compassScale < 1.0) {
          _compassOffsetX = 0.0;
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: _buildSearchBar(),
      ),
      body: Stack(
        children: [
          // 天地图（与罗盘同步旋转）
          _isLoading
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : ClipRect(
                  child: OverflowBox(
                    maxWidth: double.infinity,
                    maxHeight: double.infinity,
                    child: Transform.rotate(
                      // 计算当前罗盘的显示角度（弧度）
                      angle: -(_isLocked 
                          ? (_lockedHeading + _compassRotationOffset) % 360 
                          : _currentHeading) * pi / 180,
                      // 旋转中心点设为屏幕中心
                      alignment: Alignment.center,
                      child: SizedBox(
                        // 使用更大的尺寸确保旋转时不会裁剪（使用更大的倍数，确保任何角度旋转时都能完整显示）
                        width: MediaQuery.of(context).size.width * 3.0,
                        height: MediaQuery.of(context).size.height * 3.0,
                        child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _latitude != null && _longitude != null
                          ? LatLng(_latitude!, _longitude!)
                          : const LatLng(39.904030, 116.407526), // 默认北京天安门
                      initialZoom: 15.0,
                      minZoom: 3.0,
                      maxZoom: 18.0,
                      onMapReady: () {
                        setState(() {
                          _isMapReady = true;
                        });
                        // 地图准备好后，如果有位置信息，移动到当前位置
                        if (_latitude != null && _longitude != null) {
                          _mapController.move(
                            LatLng(_latitude!, _longitude!),
                            15.0,
                          );
                        }
                      },
                      // 根据罗盘状态动态控制地图交互
                      interactionOptions: InteractionOptions(
                        flags: (_isDragging || _isScaling)
                            ? InteractiveFlag.none // 当拖动或缩放罗盘时，完全禁用地图交互
                            : InteractiveFlag.all, // 否则允许所有交互
                      ),
                    ),
                    children: [
                      // 底图图层（根据选择显示卫星或普通地图）
                      TileLayer(
                        urlTemplate: Tianditu.tileUrlTemplate(
                          _isSatelliteMap ? 'img' : 'vec',
                        ),
                        subdomains: const ['0', '1', '2', '3', '4', '5', '6', '7'],
                        userAgentPackageName: 'com.example.flutter_application_1',
                        maxZoom: 18,
                      ),
                      // 标注图层（根据底图类型选择对应的注记图层）
                      TileLayer(
                        urlTemplate: Tianditu.tileUrlTemplate(
                          _isSatelliteMap ? 'cia' : 'cva',
                        ),
                        subdomains: const ['0', '1', '2', '3', '4', '5', '6', '7'],
                        userAgentPackageName: 'com.example.flutter_application_1',
                        maxZoom: 18,
                      ),
                      // 标记层
                      MarkerLayer(
                        markers: [
                          if (_latitude != null && _longitude != null)
                            Marker(
                              point: LatLng(_latitude!, _longitude!),
                              width: 80,
                              height: 100,
                              child: _buildArrowMarker(),
                            ),
                        ],
                      ),
                    ],
                        ),
                      ),
                    ),
                  ),
                ),
          
          // 罗盘显示在正中间（可拖动和缩放）
          if (!_isLoading)
            Positioned(
              // 根据缩放比例计算罗盘的实际显示区域（用于命中测试，防止手势穿透到地图）
              left: _compassOffsetX -
                  (MediaQuery.of(context).size.width * (_compassScale - 1.0) / 2)
                      .clamp(0.0, double.infinity),
              right: -_compassOffsetX -
                  (MediaQuery.of(context).size.width * (_compassScale - 1.0) / 2)
                      .clamp(0.0, double.infinity),
              top: MediaQuery.of(context).size.height / 2 -
                  MediaQuery.of(context).size.width * _compassScale / 2 +
                  _compassOffsetY,
              height: MediaQuery.of(context).size.width * _compassScale,
              child: GestureDetector(
                // 只使用 scale（它包含 pan），避免 “pan + scale 冗余” 的 FlutterError
                behavior: HitTestBehavior.opaque,
                onScaleStart: (details) {
                  setState(() {
                    _isDragging = true;
                    _isScaling = false;
                    _initialScale = _compassScale;
                  });
                },
                onScaleUpdate: (details) {
                  setState(() {
                    // 是否在缩放：scale != 1（scale 手势同时覆盖单指拖动与双指缩放）
                    final isScalingNow = (details.scale - 1.0).abs() > 0.001;
                    _isScaling = isScalingNow;
                    _isDragging = true;

                    if (isScalingNow) {
                      // 缩放
                      double newScale = (_initialScale * details.scale).clamp(0.3, 2.5);
                      _compassScale = newScale;

                      // 缩放小于 1 时，重置水平偏移（避免出现空白区）
                      if (_compassScale < 1.0) {
                        _compassOffsetX = 0.0;
                      } else {
                        // 限制水平偏移范围
                        final screenWidth = MediaQuery.of(context).size.width;
                        final compassWidth = screenWidth * _compassScale;
                        final overflow = (compassWidth - screenWidth) / 2;
                        _compassOffsetX = _compassOffsetX.clamp(-overflow, overflow);
                      }
                    } else {
                      // 单指拖动（用 focalPointDelta）
                      final delta = details.focalPointDelta;

                      _compassOffsetY += delta.dy;
                      final screenHeight = MediaQuery.of(context).size.height;
                      final maxOffset = screenHeight / 2;
                      _compassOffsetY = _compassOffsetY.clamp(-maxOffset, maxOffset);

                      if (_compassScale > 1.0) {
                        final screenWidth = MediaQuery.of(context).size.width;
                        final compassWidth = screenWidth * _compassScale;
                        final overflow = (compassWidth - screenWidth) / 2;

                        _compassOffsetX += delta.dx;
                        _compassOffsetX = _compassOffsetX.clamp(-overflow, overflow);
                      }
                    }
                  });
                },
                onScaleEnd: (details) {
                  setState(() {
                    _isDragging = false;
                    _isScaling = false;
                  });

                  // 缩放结束后：小于 1 回弹到 1；否则 clamp 到 [1, 2.5]
                  if (_compassScale < 1.0) {
                    _animateScaleTo(1.0);
                  } else {
                    setState(() {
                      _compassScale = _compassScale.clamp(1.0, 2.5);
                      final screenWidth = MediaQuery.of(context).size.width;
                      final compassWidth = screenWidth * _compassScale;
                      final overflow = (compassWidth - screenWidth) / 2;
                      _compassOffsetX = _compassOffsetX.clamp(-overflow, overflow);
                    });
                  }
                },
                child: Transform.scale(
                  scale: _compassScale,
                  child: _buildCompass(_isLocked 
                      ? (_lockedHeading + _compassRotationOffset) % 360 
                      : _currentHeading),
                ),
              ),
            ),
          
          // 顶部信息栏
          Positioned(
            top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
            left: 0,
            right: 0,
            child: _buildTopInfo(),
          ),
          
          // 右上角地图类型切换按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
            right: 16,
            child: _buildMapTypeSwitch(),
          ),
          
          // 右侧控制按钮（定位、放大、缩小）
          Positioned(
            right: 16,
            top: MediaQuery.of(context).padding.top + kToolbarHeight + 50, // 向上移动更多，为旋转调整面板留出更多空间
            child: _buildMapControlButtons(),
          ),
          
          // 左下角透明度按钮
          Positioned(
            left: 16,
            bottom: 16,
            child: _buildTransparencyButton(),
          ),
          
          // 右下角锁定按钮
          Positioned(
            right: 16,
            bottom: 16,
            child: _buildLockButton(),
          ),
          
          // 旋转调整面板（当锁定且显示时）
          if (_showRotationPanel && _isLocked)
            _buildRotationPanel(),

          // 地址自动检索列表（置于最上层）
          if (_showSearchSuggestions)
            Positioned(
              top: MediaQuery.of(context).padding.top + kToolbarHeight,
              left: 0,
              right: 0,
              child: _buildSearchSuggestionsPanel(),
            ),
        ],
      ),
    );
  }
  
  // 构建锁定按钮
  Widget _buildLockButton() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _toggleLock();
          },
          borderRadius: BorderRadius.circular(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isLocked ? Icons.lock : Icons.lock_open,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(height: 2),
              Text(
                _isLocked ? '已锁定' : '未锁定',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // 切换锁定状态
  void _toggleLock() {
    setState(() {
      if (_isLocked) {
        // 如果已锁定，则解锁并隐藏调整面板
        _isLocked = false;
        _showRotationPanel = false;
        _compassRotationOffset = 0.0; // 重置偏移角度
      } else {
        // 如果未锁定，则锁定并显示调整面板
        _isLocked = true;
        _lockedHeading = _currentHeading; // 保存当前角度作为基础角度
        _compassRotationOffset = 0.0; // 重置偏移角度
        _showRotationPanel = true; // 显示调整面板
      }
    });
  }
  
  // 构建旋转调整面板
  Widget _buildRotationPanel() {
    return Positioned(
      right: 16,
      top: MediaQuery.of(context).padding.top + kToolbarHeight + 80 + 180, // 在右侧按钮下方（按钮高度56*3+间距12*2=192，再加一些间距）
      child: Listener(
        onPointerDown: (event) {
          // 指针按下
        },
        onPointerMove: (event) {
          // 上下滑动调整角度
          if (!_isLocked) {
            return;
          }
          
          double sensitivity = 0.5; // 灵敏度
          double delta = -event.delta.dy * sensitivity;
          double newOffset = (_compassRotationOffset + delta).clamp(-180.0, 180.0);
          
          if ((newOffset - _compassRotationOffset).abs() > 0.01) {
            setState(() {
              _compassRotationOffset = newOffset;
            });
          }
        },
        onPointerUp: (event) {
          // 指针抬起
        },
        child: GestureDetector(
          onPanStart: (details) {
            // 开始滑动
          },
          onPanUpdate: (details) {
            // 上下滑动调整角度
            // 向上滑动增加角度，向下滑动减少角度
            if (!_isLocked) {
              return;
            }
            
            double sensitivity = 0.5; // 灵敏度
            double delta = -details.delta.dy * sensitivity;
            double newOffset = (_compassRotationOffset + delta).clamp(-180.0, 180.0);
            
            if ((newOffset - _compassRotationOffset).abs() > 0.01) {
              setState(() {
                _compassRotationOffset = newOffset;
              });
            }
          },
          onPanEnd: (details) {
            // 滑动结束
          },
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 60,
            constraints: const BoxConstraints(
              minHeight: 250, // 最小高度，确保能包住所有文字
            ),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.4),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.white.withOpacity(0.5),
                width: 2,
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
      ),
    );
  }
  
  // 构建透明度按钮
  Widget _buildTransparencyButton() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _showTransparencyBottomSheet();
          },
          borderRadius: BorderRadius.circular(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 网格图标（4x4）
              CustomPaint(
                size: const Size(24, 24),
                painter: GridIconPainter(),
              ),
              const SizedBox(height: 2),
              const Text(
                '透明度',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // 显示透明度设置抽屉
  void _showTransparencyBottomSheet() {
    double tempOpacity = _compassOpacity;
    bool tempUseBlackLine = _useBlackLine;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.4,
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
                        '设置透明度',
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
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 滑块
                          Slider(
                            value: tempOpacity,
                            min: 0.0,
                            max: 1.0,
                            divisions: 100,
                            activeColor: Colors.red,
                            inactiveColor: Colors.grey[300],
                            onChanged: (value) {
                              setModalState(() {
                                tempOpacity = value;
                              });
                              // 实时更新透明度
                              setState(() {
                                _compassOpacity = value;
                              });
                            },
                          ),
                          const SizedBox(height: 24),
                          // 单选按钮
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              // 白线条选项
                              GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    tempUseBlackLine = false;
                                  });
                                  setState(() {
                                    _useBlackLine = false;
                                  });
                                },
                                child: Row(
                                  children: [
                                    Radio<bool>(
                                      value: false,
                                      groupValue: tempUseBlackLine,
                                      onChanged: (bool? value) {
                                        if (value != null) {
                                          setModalState(() {
                                            tempUseBlackLine = value;
                                          });
                                          setState(() {
                                            _useBlackLine = value;
                                          });
                                        }
                                      },
                                      activeColor: Colors.red,
                                    ),
                                    const Text(
                                      '白线条',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // 黑线条选项
                              GestureDetector(
                                onTap: () {
                                  setModalState(() {
                                    tempUseBlackLine = true;
                                  });
                                  setState(() {
                                    _useBlackLine = true;
                                  });
                                },
                                child: Row(
                                  children: [
                                    Radio<bool>(
                                      value: true,
                                      groupValue: tempUseBlackLine,
                                      onChanged: (bool? value) {
                                        if (value != null) {
                                          setModalState(() {
                                            tempUseBlackLine = value;
                                          });
                                          setState(() {
                                            _useBlackLine = value;
                                          });
                                        }
                                      },
                                      activeColor: Colors.red,
                                    ),
                                    const Text(
                                      '黑线条',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          // 确定按钮
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _compassOpacity = tempOpacity;
                                  _useBlackLine = tempUseBlackLine;
                                });
                                Navigator.pop(context);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                '确定',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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
  
  // 构建地图控制按钮
  Widget _buildMapControlButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 定位按钮
        _buildControlButton(
          icon: Icons.my_location,
          label: '定位',
          onPressed: _locateToCurrentPosition,
        ),
        const SizedBox(height: 12),
        // 放大按钮
        _buildControlButton(
          icon: Icons.add,
          label: '放大',
          onPressed: _zoomIn,
        ),
        const SizedBox(height: 12),
        // 缩小按钮
        _buildControlButton(
          icon: Icons.remove,
          label: '缩小',
          onPressed: _zoomOut,
        ),
      ],
    );
  }
  
  // 构建地图类型切换按钮
  Widget _buildMapTypeSwitch() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 卫星按钮
          GestureDetector(
            onTap: () {
              setState(() {
                _isSatelliteMap = true;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _isSatelliteMap ? Colors.white : Colors.transparent,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
              child: Text(
                '卫星',
                style: TextStyle(
                  color: _isSatelliteMap ? Colors.black : Colors.white,
                  fontSize: 12,
                  fontWeight: _isSatelliteMap ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
          // 普通按钮
          GestureDetector(
            onTap: () {
              setState(() {
                _isSatelliteMap = false;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: !_isSatelliteMap ? Colors.white : Colors.transparent,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: Text(
                '普通',
                style: TextStyle(
                  color: !_isSatelliteMap ? Colors.black : Colors.white,
                  fontSize: 12,
                  fontWeight: !_isSatelliteMap ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // 构建单个控制按钮
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // 定位到当前位置
  void _locateToCurrentPosition() {
    if (!_isMapReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('地图尚未准备好')),
      );
      return;
    }
    
    if (_latitude == null || _longitude == null) {
      // 如果没有位置信息，先获取位置
      _getLocation().then((_) {
        if (_latitude != null && _longitude != null && _isMapReady) {
          _mapController.move(
            LatLng(_latitude!, _longitude!),
            15.0,
          );
        }
      });
    } else {
      // 直接移动到当前位置
      _mapController.move(
        LatLng(_latitude!, _longitude!),
        15.0,
      );
    }
  }
  
  // 放大地图
  void _zoomIn() {
    if (!_isMapReady) {
      return;
    }
    
    final currentZoom = _mapController.camera?.zoom ?? 15.0;
    final newZoom = (currentZoom + 1).clamp(3.0, 18.0);
    final center = _mapController.camera?.center ?? 
        (_latitude != null && _longitude != null 
            ? LatLng(_latitude!, _longitude!)
            : const LatLng(39.904030, 116.407526));
    
    _mapController.move(center, newZoom);
  }
  
  // 缩小地图
  void _zoomOut() {
    if (!_isMapReady) {
      return;
    }
    
    final currentZoom = _mapController.camera?.zoom ?? 15.0;
    final newZoom = (currentZoom - 1).clamp(3.0, 18.0);
    final center = _mapController.camera?.center ?? 
        (_latitude != null && _longitude != null 
            ? LatLng(_latitude!, _longitude!)
            : const LatLng(39.904030, 116.407526));
    
    _mapController.move(center, newZoom);
  }

  // 构建罗盘
  Widget _buildCompass(double heading) {
    final finalHeading = heading % 360;
    return Stack(
      alignment: Alignment.center,
      children: [
        // 罗盘背景图片：
        // 地图罗盘始终使用 touming-* 目录下与当前罗盘同名的透明盘面图，
        // 根据 _useBlackLine 选择黑线条或白线条版本
        Transform.rotate(
          angle: (-finalHeading * pi / 180 + pi / 2), // 旋转罗盘背景
          child: Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.width,
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
              child: Opacity(
                opacity: _compassOpacity,
                child: Builder(
                  builder: (context) {
                    // 从当前罗盘路径中提取文件名部分
                    final fileName = _compassImagePath.split('/').last;
                    final bgPath = _useBlackLine
                        ? 'assets/touming-black/$fileName'
                        : 'assets/touming-white/$fileName';

                    return AppAssetImage(
                      assetPath: bgPath,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.amber,
                          child: const Center(
                            child: Icon(Icons.error, color: Colors.white, size: 50),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        
        // 中心十字线和气泡
        Stack(
          alignment: Alignment.center,
          children: [
            // 十字线（红色）
            CustomPaint(
              size: Size(MediaQuery.of(context).size.width, MediaQuery.of(context).size.width),
              painter: CrosshairPainter(
                lineColor: Colors.red,
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
            // 指南针指针
            Transform.rotate(
              angle: 0, // 指针始终指向磁北
              child: CustomPaint(
                size: const Size(60, 60),
                painter: CompassNeedlePainter(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 构建蓝色箭头标记
  Widget _buildArrowMarker() {
    // 箭头标记不需要旋转，因为地图已经旋转了
    // 箭头应该始终指向地图的上方（即罗盘指向的方向）
    return Transform.rotate(
      angle: 0, // 箭头不旋转，因为地图已经旋转了
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 蓝色箭头
          CustomPaint(
            size: const Size(50, 60),
            painter: ArrowPainter(),
          ),
          const SizedBox(height: 4),
          // "我的位置"文字
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF2196F3).withOpacity(0.9),
              borderRadius: BorderRadius.circular(4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Text(
              '我的位置',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopInfo() {
    final direction = _getDirection(_heading);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：山向和方向度数
          Text(
            '${formatMountainFacing(_heading)} $direction${_heading.toStringAsFixed(1)}°',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          // 第二行：经纬度和海拔按钮
          Row(
            children: [
              if (_latitude != null && _longitude != null)
                Text(
                  '北纬${_formatCoordinate(_latitude!, true)} 东经${_formatCoordinate(_longitude!, false)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isSatelliteMap ? Colors.white : Colors.grey[700], // 卫星地图时使用白色
                  ),
                )
              else
                Text(
                  '获取位置中...',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isSatelliteMap ? Colors.white : Colors.grey[600], // 卫星地图时使用白色
                  ),
                ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  _showAltitudeBottomSheet();
                },
                child: Text(
                  '海拔 >>',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue[700],
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black,
          ),
        ),
      ],
    );
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

  // 显示海拔信息底部抽屉
  void _showAltitudeBottomSheet() {
    // 开始获取位置和气压
    _getLocationForAltitude();
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

  // 获取位置信息（用于海拔抽屉）
  Future<void> _getLocationForAltitude() async {
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
          _isLoadingAltitude = false;
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
            _isLoadingAltitude = false;
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
          _isLoadingAltitude = false;
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
        print('位置获取成功: 纬度=${_latitude}, 经度=${_longitude}, 海拔=${_altitude}');
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
}

// 十字线绘制器
class CrosshairPainter extends CustomPainter {
  final Color lineColor;
  
  CrosshairPainter({this.lineColor = Colors.red});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 2
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    if (oldDelegate is CrosshairPainter) {
      return oldDelegate.lineColor != lineColor;
    }
    return true;
  }
}

// 网格图标绘制器（4x4网格）
class GridIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // 绘制4x4网格
    final cellWidth = size.width / 4;
    final cellHeight = size.height / 4;
    
    // 绘制垂直线
    for (int i = 1; i < 4; i++) {
      canvas.drawLine(
        Offset(i * cellWidth, 0),
        Offset(i * cellWidth, size.height),
        paint,
      );
    }
    
    // 绘制水平线
    for (int i = 1; i < 4; i++) {
      canvas.drawLine(
        Offset(0, i * cellHeight),
        Offset(size.width, i * cellHeight),
        paint,
      );
    }
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

    final path = ui.Path();
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

// 箭头绘制器
class ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF2196F3)
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = ui.Path();
    final centerX = size.width / 2;
    
    // 绘制箭头形状
    path.moveTo(centerX, 0); // 顶部尖点
    path.lineTo(size.width * 0.75, size.height * 0.7); // 右上
    path.lineTo(size.width * 0.6, size.height * 0.7); // 右中
    path.lineTo(size.width * 0.6, size.height); // 右下
    path.lineTo(size.width * 0.4, size.height); // 左下
    path.lineTo(size.width * 0.4, size.height * 0.7); // 左中
    path.lineTo(size.width * 0.25, size.height * 0.7); // 左上
    path.close();

    // 绘制阴影
    canvas.save();
    canvas.translate(0, 2);
    canvas.drawPath(path, Paint()..color = Colors.black.withOpacity(0.2));
    canvas.restore();

    // 绘制箭头
    canvas.drawPath(path, paint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
