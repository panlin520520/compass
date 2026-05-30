import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'tianditu.dart';

/// “截取地图”页面：选择天地图底图位置与类型，点击“截取”返回当前中心/缩放/图层类型。
class TiandituPickMapPage extends StatefulWidget {
  const TiandituPickMapPage({
    super.key,
    this.initialCenter,
    this.initialZoom = 16,
    this.initialSatellite = false,
  });

  final LatLng? initialCenter;
  final double initialZoom;
  final bool initialSatellite;

  @override
  State<TiandituPickMapPage> createState() => _TiandituPickMapPageState();
}

class _TiandituPickMapPageState extends State<TiandituPickMapPage> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool _isSatellite = false;
  bool _isMapReady = false;
  bool _isLocating = false;
  Timer? _searchDebounce;
  List<TiandituSearchSuggestion> _searchSuggestions = [];
  bool _isSearchSuggesting = false;
  bool _showSearchSuggestions = false;
  int _searchRequestId = 0;

  LatLng _center = const LatLng(39.904030, 116.407526); // 默认北京天安门
  double _zoom = 16;

  static const double _searchBarTopOffset = 56;
  static const double _searchBarHeight = 48;

  @override
  void initState() {
    super.initState();
    _isSatellite = widget.initialSatellite;
    _center = widget.initialCenter ?? _center;
    _zoom = widget.initialZoom;
    _searchFocus.addListener(_onSearchFocusChanged);

    // 页面打开时，尽量先定位到当前位置
    unawaited(_moveToCurrentLocation(showToastOnFail: false));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchFocus.removeListener(_onSearchFocusChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
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
      final bound = TiandituSearch.mapBoundAround(_center.longitude, _center.latitude);
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

  Future<void> _moveToCoordinates(double lat, double lon) async {
    final target = LatLng(lat, lon);
    _center = target;
    if (_isMapReady) {
      _mapController.move(target, _zoom);
    }
    if (mounted) setState(() {});
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
    await _moveToCoordinates(item.latitude, item.longitude);
  }

  Future<void> _moveToCurrentLocation({required bool showToastOnFail}) async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (showToastOnFail && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请启用位置服务')),
          );
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (showToastOnFail && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('需要位置权限')),
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final target = LatLng(pos.latitude, pos.longitude);

      _center = target;
      if (_isMapReady) {
        _mapController.move(target, _zoom);
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (showToastOnFail && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('定位失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
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
      final bound = TiandituSearch.mapBoundAround(_center.longitude, _center.latitude);
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

  void _zoomIn() {
    if (!_isMapReady) return;
    final next = (_mapController.camera.zoom + 1).clamp(3.0, 18.0);
    _mapController.move(_mapController.camera.center, next);
  }

  void _zoomOut() {
    if (!_isMapReady) return;
    final next = (_mapController.camera.zoom - 1).clamp(3.0, 18.0);
    _mapController.move(_mapController.camera.center, next);
  }

  void _onCapture() {
    if (!_isMapReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('地图尚未准备好')),
      );
      return;
    }

    final camera = _mapController.camera;
    Navigator.of(context).pop(
      TiandituMapSelection(
        center: camera.center,
        zoom: camera.zoom,
        isSatellite: _isSatellite,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 地图
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: _zoom,
                minZoom: 3,
                maxZoom: 18,
                onMapReady: () {
                  setState(() => _isMapReady = true);
                  // 初始定位一次（如果 initState 定位比 mapReady 慢）
                  if (widget.initialCenter == null) {
                    unawaited(_moveToCurrentLocation(showToastOnFail: false));
                  }
                },
                onPositionChanged: (pos, _) {
                  if (!mounted) return;
                  setState(() {
                    if (pos.center != null) _center = pos.center!;
                    _zoom = pos.zoom ?? _zoom;
                  });
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: Tianditu.tileUrlTemplate(
                    _isSatellite ? 'img' : 'vec',
                  ),
                  subdomains: const ['0', '1', '2', '3', '4', '5', '6', '7'],
                  userAgentPackageName: 'com.example.flutter_application_1',
                  maxZoom: 18,
                ),
                TileLayer(
                  urlTemplate: Tianditu.tileUrlTemplate(
                    _isSatellite ? 'cia' : 'cva',
                  ),
                  subdomains: const ['0', '1', '2', '3', '4', '5', '6', '7'],
                  userAgentPackageName: 'com.example.flutter_application_1',
                  maxZoom: 18,
                ),
                // 中心点标记（简单指示）
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _center,
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.navigation,
                        size: 28,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 顶部栏（返回 + 标题）
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Container(
              padding: EdgeInsets.only(top: topPadding),
              color: Colors.white.withOpacity(0.92),
              child: SizedBox(
                height: 48,
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const Expanded(
                      child: Center(
                        child: Text(
                          '截取地图',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 48), // 占位，保证标题居中
                  ],
                ),
              ),
            ),
          ),

          // 搜索框
          Positioned(
            left: 16,
            right: 16,
            top: topPadding + _searchBarTopOffset,
            child: Material(
              elevation: 6,
              shadowColor: Colors.black.withOpacity(0.12),
              borderRadius: BorderRadius.circular(24),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '请输入搜索地址',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: _clearSearch,
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
            ),
          ),

          // 地址自动补全列表
          if (_showSearchSuggestions)
            Positioned(
              left: 16,
              right: 16,
              top: topPadding + _searchBarTopOffset + _searchBarHeight,
              child: _buildSearchSuggestionsPanel(),
            ),

          // 右上角图层选择
          Positioned(
            right: 16,
            top: topPadding + 124,
            child: _MapTypeChip(
              isSatellite: _isSatellite,
              onChanged: (v) => setState(() => _isSatellite = v),
            ),
          ),

          // 右侧控制按钮（定位/放大/缩小）
          Positioned(
            right: 16,
            top: topPadding + 190,
            child: Column(
              children: [
                _RoundActionButton(
                  label: '定位',
                  icon: _isLocating ? Icons.my_location : Icons.place,
                  onTap: () => _moveToCurrentLocation(showToastOnFail: true),
                ),
                const SizedBox(height: 10),
                _RoundActionButton(
                  label: '放大',
                  icon: Icons.add,
                  onTap: _zoomIn,
                ),
                const SizedBox(height: 10),
                _RoundActionButton(
                  label: '缩小',
                  icon: Icons.remove,
                  onTap: _zoomOut,
                ),
              ],
            ),
          ),

          // 底部截取按钮
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _onCapture,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    '截取',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapTypeChip extends StatelessWidget {
  const _MapTypeChip({
    required this.isSatellite,
    required this.onChanged,
  });

  final bool isSatellite;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = isSatellite ? '天地影像' : '天地标准';
    return Material(
      color: Colors.black.withOpacity(0.70),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => onChanged(!isSatellite),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundActionButton extends StatelessWidget {
  const _RoundActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withOpacity(0.70),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

