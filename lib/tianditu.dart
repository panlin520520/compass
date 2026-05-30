import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// 天地图配置与工具方法（flutter_map TileLayer 使用）
///
/// 注意：天地图服务需要 `tk`（Key）。请替换为你自己申请的 Key。
/// 申请入口（示例）：`https://www.tianditu.gov.cn/`
class Tianditu {
  /// 默认 Key（建议替换为你自己的）
  static const String key = 'f0576ee98fee441572f810faec5a6524';

  /// 天地图瓦片 URL 模板（flutter_map 的 TileLayer.urlTemplate）
  ///
  /// type:
  /// - `vec` 矢量底图（普通）
  /// - `img` 影像底图（卫星）
  /// - `ter` 地形底图
  /// - `cva` 矢量注记
  /// - `cia` 影像注记
  /// - `cta` 地形注记
  static String tileUrlTemplate(String type, {String? tk}) {
    final keyToUse = tk ?? key;
    return 'https://t{s}.tianditu.gov.cn/DataServer?T=${type}_w&x={x}&y={y}&l={z}&tk=$keyToUse';
  }
}

/// 天地图地址检索建议项
class TiandituSearchSuggestion {
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  const TiandituSearchSuggestion({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  String get displayText {
    if (address.isEmpty) return name;
    if (name.isEmpty) return address;
    return '$name,$address';
  }
}

/// 天地图地名搜索（地址自动检索）
class TiandituSearch {
  static const _searchUrl = 'http://api.tianditu.gov.cn/v2/search';

  /// 根据关键字获取地址建议列表（queryType=7 地名搜索）
  static Future<List<TiandituSearchSuggestion>> suggest(
    String keyword, {
    String? mapBound,
    int count = 10,
    String? tk,
  }) async {
    final q = keyword.trim();
    if (q.isEmpty) return [];

    final bound = mapBound ?? '73.66,3.86,135.05,53.55';
    final postStr = jsonEncode({
      'keyWord': q,
      'level': 12,
      'mapBound': bound,
      'queryType': 7,
      'start': 0,
      'count': count,
    });

    final uri = Uri.parse(_searchUrl).replace(
      queryParameters: {
        'postStr': postStr,
        'type': 'query',
        'tk': tk ?? Tianditu.key,
      },
    );

    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body);
    if (data is! Map) return [];

    final status = data['status'];
    if (status is Map && status['infocode'] != 1000) return [];

    final pois = data['pois'];
    if (pois is! List) return [];

    final results = <TiandituSearchSuggestion>[];
    for (final item in pois) {
      if (item is! Map) continue;
      final name = (item['name'] ?? '').toString();
      final address = (item['address'] ?? '').toString();
      final lonlat = (item['lonlat'] ?? '').toString();
      final parts = lonlat.split(',');
      if (parts.length != 2) continue;
      final lon = double.tryParse(parts[0].trim());
      final lat = double.tryParse(parts[1].trim());
      if (lon == null || lat == null) continue;
      results.add(TiandituSearchSuggestion(
        name: name,
        address: address,
        latitude: lat,
        longitude: lon,
      ));
    }
    return results;
  }

  /// 根据当前中心点生成检索范围（约 ±1°）
  static String mapBoundAround(double lon, double lat) {
    return '${lon - 1},${lat - 1},${lon + 1},${lat + 1}';
  }
}

/// “截取地图/选择底图”页面返回的地图状态
class TiandituMapSelection {
  final LatLng center;
  final double zoom;
  final bool isSatellite;

  const TiandituMapSelection({
    required this.center,
    required this.zoom,
    required this.isSatellite,
  });
}

