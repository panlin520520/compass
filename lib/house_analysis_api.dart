import 'dart:convert';
import 'package:http/http.dart' as http;

const String _baseUrl = 'http://aidashi.net/home/Index/luopan_fangwufenxi';

/// POST 表单编码，支持中文
String _encodeFormBody(Map<String, String> params) {
  return params.entries
      .map((e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');
}

/// 玄空飞星
class XuanKongFeiXingItem {
  XuanKongFeiXingItem({
    required this.gongNum,
    required this.mountainNum,
    required this.waterNum,
    required this.yunNum,
    required this.isMountain,
    required this.isDirection,
  });
  final int gongNum;
  final int mountainNum;
  final int waterNum;
  final int yunNum;
  final bool isMountain;
  final bool isDirection;

  factory XuanKongFeiXingItem.fromJson(Map<String, dynamic> json) {
    return XuanKongFeiXingItem(
      gongNum: _intFromJson(json['gongNum']),
      mountainNum: _intFromJson(json['mountainNum']),
      waterNum: _intFromJson(json['waterNum']),
      yunNum: _intFromJson(json['yunNum']),
      isMountain: json['isMountain'] == true,
      isDirection: json['isDirection'] == true,
    );
  }
  static int _intFromJson(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }
}

/// 八宅
class EightMansionsItem {
  EightMansionsItem({
    required this.gongNum,
    required this.direction,
    required this.star,
    required this.luck,
    required this.energy,
  });
  final int gongNum;
  final String direction;
  final String star;
  final String luck;
  final String energy;

  factory EightMansionsItem.fromJson(Map<String, dynamic> json) {
    return EightMansionsItem(
      gongNum: XuanKongFeiXingItem._intFromJson(json['gongNum']),
      direction: json['direction']?.toString() ?? '',
      star: json['star']?.toString() ?? '',
      luck: json['luck']?.toString() ?? '',
      energy: json['energy']?.toString() ?? '',
    );
  }
}

/// 流年
class LiuNianItem {
  LiuNianItem({
    required this.gongNum,
    required this.star,
    required this.shensha,
    required this.nature,
    required this.wx,
  });
  final int gongNum;
  final String star;
  final String shensha;
  final String nature;
  final String wx;

  factory LiuNianItem.fromJson(Map<String, dynamic> json) {
    return LiuNianItem(
      gongNum: XuanKongFeiXingItem._intFromJson(json['gongNum']),
      star: json['star']?.toString() ?? '',
      shensha: json['shensha']?.toString() ?? '',
      nature: json['nature']?.toString() ?? '',
      wx: json['wx']?.toString() ?? '',
    );
  }
}

class HouseAnalysisResponse {
  HouseAnalysisResponse({
    required this.xuanKongFeiXing,
    this.xuanKongFeiXingTigua,
    required this.eightMansionsCompass,
    required this.liuNian,
  });
  final List<XuanKongFeiXingItem> xuanKongFeiXing;
  final List<XuanKongFeiXingItem>? xuanKongFeiXingTigua;
  final List<EightMansionsItem> eightMansionsCompass;
  final List<LiuNianItem> liuNian;

  factory HouseAnalysisResponse.fromJson(Map<String, dynamic> json) {
    List<XuanKongFeiXingItem> parseXuanKong(dynamic list) {
      if (list == null || list is! List) return [];
      return list
          .map((e) => XuanKongFeiXingItem.fromJson(
              e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e)))
          .toList();
    }

    return HouseAnalysisResponse(
      xuanKongFeiXing: parseXuanKong(json['xuanKongFeiXing']),
      xuanKongFeiXingTigua: json['xuanKongFeiXing_tigua'] != null
          ? parseXuanKong(json['xuanKongFeiXing_tigua'])
          : null,
      eightMansionsCompass: (json['eightMansionsCompass'] as List?)
              ?.map((e) => EightMansionsItem.fromJson(
                  e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e)))
              .toList() ??
          [],
      liuNian: (json['liuNian'] as List?)
              ?.map((e) => LiuNianItem.fromJson(
                  e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e)))
              .toList() ??
          [],
    );
  }
}

/// 请求房屋分析接口
/// [period] 运数 1-9
/// [mountain] 坐 如：子
/// [direction] 向 如：午
Future<HouseAnalysisResponse?> fetchHouseAnalysis({
  required int period,
  required String mountain,
  required String direction,
}) async {
  try {
    final params = {
      'period': period.toString(),
      'mountain': mountain,
      'direction': direction,
    };
    final body = _encodeFormBody(params);
    
    // 调试：打印请求参数
    print('========== 房屋分析接口请求参数 ==========');
    print('请求URL: $_baseUrl');
    print('请求参数: period=$period, mountain=$mountain, direction=$direction');
    print('编码后的Body: $body');
    print('==========================================');
    
    final res = await http.post(
      Uri.parse(_baseUrl),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
      },
      body: body,
      encoding: utf8,
    );
    if (res.statusCode != 200) return null;
    final map = jsonDecode(res.body) as Map<String, dynamic>?;
    if (map == null) return null;
    
    // 调试：打印原始JSON数据
    print('========== API返回的原始数据 ==========');
    print('xuanKongFeiXing原始数据: ${map['xuanKongFeiXing']}');
    if (map['xuanKongFeiXing'] != null && map['xuanKongFeiXing'] is List) {
      final list = map['xuanKongFeiXing'] as List;
      for (var i = 0; i < list.length; i++) {
        final item = list[i];
        print('索引$i: gongNum=${item['gongNum']}, mountainNum=${item['mountainNum']}, waterNum=${item['waterNum']}');
      }
    }
    print('==========================================');
    
    return HouseAnalysisResponse.fromJson(map);
  } catch (_) {
    return null;
  }
}
