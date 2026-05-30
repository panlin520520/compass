import 'dart:convert';

import 'api_config.dart';

/// 智能读盘（默认提示）：优先加载 **纯 ASCII 路径** 的合并包 [default_tip_layers.json]，
/// 避免中文路径在 Windows / AssetManifest 下无法匹配导致列表为空。
class DefaultTipJsonCatalog {
  DefaultTipJsonCatalog._();

  static const String _folderPrefix = 'assets/default-tip-json/';
  static const String _packedAssetPath = 'assets/default_tip_layers.json';

  static const String _indexAssetPath = 'assets/default-tip-json/index.json';

  /// 默认提示 · 智能读盘列表顺序（与文件名一致，不含 .json）
  static const List<String> displayOrder = <String>[
    '先天八卦_卦位',
    '后天八卦_卦位',
    '先天八卦洛书数',
    '地盘正针二十四山',
    '穿山72龙',
    '地盘正针百二十分金',
    '人盘中针二十四山',
    '透地平分六十龙',
    '天盘缝针二十四山',
    '天盘缝针百二十分金',
    '先天方圆六十四卦内卦',
    '先天方圆六十四卦外卦',
    '六十甲配六十四卦五行',
    '正兼向度数指标',
    '二十八星宿',
  ];

  static const List<String> _explicitAssetPaths = <String>[
    'assets/default-tip-json/先天八卦_卦位.json',
    'assets/default-tip-json/后天八卦_卦位.json',
    'assets/default-tip-json/先天八卦洛书数.json',
    'assets/default-tip-json/地盘正针二十四山.json',
    'assets/default-tip-json/穿山72龙.json',
    'assets/default-tip-json/地盘正针百二十分金.json',
    'assets/default-tip-json/人盘中针二十四山.json',
    'assets/default-tip-json/透地平分六十龙.json',
    'assets/default-tip-json/天盘缝针二十四山.json',
    'assets/default-tip-json/天盘缝针百二十分金.json',
    'assets/default-tip-json/先天方圆六十四卦内卦.json',
    'assets/default-tip-json/先天方圆六十四卦外卦.json',
    'assets/default-tip-json/六十甲配六十四卦五行.json',
    'assets/default-tip-json/正兼向度数指标.json',
    'assets/default-tip-json/二十八星宿.json',
  ];

  static void sortEntries(List<DefaultTipJsonEntry> out) {
    int rank(String name) {
      final i = displayOrder.indexOf(name);
      return i >= 0 ? i : displayOrder.length + 1;
    }

    out.sort((a, b) {
      final ra = rank(a.displayName);
      final rb = rank(b.displayName);
      if (ra != rb) return ra.compareTo(rb);
      return a.displayName.compareTo(b.displayName);
    });
  }

  static Future<String?> _loadUtf8ByLogicalPath(String logicalPath) async {
    final norm = Uri.decodeFull(logicalPath.replaceAll('\\', '/'));
    return loadAppAssetString(norm);
  }

  static Future<List<String>> _enumerateJsonLogicalPaths() async {
    final out = <String>[];

    final indexText = await _loadUtf8ByLogicalPath(_indexAssetPath);
    if (indexText != null) {
      try {
        final list = json.decode(indexText) as List<dynamic>;
        for (final e in list) {
          if (e is! String) continue;
          if (!e.toLowerCase().endsWith('.json')) continue;
          if (e == 'index.json') continue;
          out.add('$_folderPrefix$e');
        }
      } catch (_) {}
    }

    if (out.isNotEmpty) {
      return out;
    }

    for (final p in _explicitAssetPaths) {
      out.add(p);
    }
    return out;
  }

  static Future<List<DefaultTipJsonEntry>> _loadFromSeparateFiles() async {
    final paths = await _enumerateJsonLogicalPaths();
    final out = <DefaultTipJsonEntry>[];
    for (final logical in paths) {
      final raw = await _loadUtf8ByLogicalPath(logical);
      if (raw == null) continue;
      try {
        final decoded = json.decode(raw);
        final file = logical.split('/').last;
        final name =
            file.endsWith('.json') ? file.substring(0, file.length - 5) : file;
        out.add(DefaultTipJsonEntry(displayName: name, root: decoded));
      } catch (_) {}
    }
    sortEntries(out);
    return out;
  }

  /// 主入口：先读合并包（ASCII 文件名），失败再尝试分散 JSON。
  static Future<List<DefaultTipJsonEntry>> load() async {
    final packed = await _loadUtf8ByLogicalPath(_packedAssetPath);
    if (packed != null) {
      try {
        final map = json.decode(packed) as Map<String, dynamic>;
        final out = <DefaultTipJsonEntry>[];
        for (final e in map.entries) {
          out.add(DefaultTipJsonEntry(displayName: e.key, root: e.value));
        }
        sortEntries(out);
        if (out.isNotEmpty) return out;
      } catch (_) {}
    }

    return _loadFromSeparateFiles();
  }

  /// 返回当前角度命中的原始行（含 `坐`/`向` 等字段），供山水六十龙等联动解析。
  static Map<String, dynamic>? matchRowData({
    required double sittingDegree,
    required double facingDialDegree,
    required dynamic root,
    String? layerName,
  }) {
    if (root is List) {
      return _scanListData(sittingDegree, facingDialDegree, root);
    }
    if (root is Map) {
      final map = Map<String, dynamic>.from(root);
      if (layerName != null && map[layerName] is List) {
        return _scanListData(
          sittingDegree,
          facingDialDegree,
          map[layerName] as List<dynamic>,
        );
      }
      final listValues = map.values.whereType<List>().toList();
      if (listValues.length == 1) {
        return _scanListData(
          sittingDegree,
          facingDialDegree,
          listValues.first as List<dynamic>,
        );
      }
      for (final value in map.values) {
        if (value is List) {
          final hit = _scanListData(
            sittingDegree,
            facingDialDegree,
            value as List<dynamic>,
          );
          if (hit != null) return hit;
        }
      }
    }
    return null;
  }

  static String? matchRow({
    required double sittingDegree,
    required double facingDialDegree,
    required dynamic root,
    String? layerName,
  }) {
    if (layerName == '二十八星宿') {
      return matchTwentyEightStarLayer(
        sittingDegree: sittingDegree,
        facingDialDegree: facingDialDegree,
        root: root,
      );
    }
    final row = matchRowData(
      sittingDegree: sittingDegree,
      facingDialDegree: facingDialDegree,
      root: root,
      layerName: layerName,
    );
    if (row == null) return null;
    return _formatMatchedRow(row, layerName: layerName);
  }

  /// 二十八星宿：向、坐分别按罗盘度数在 [二十八星宿.json] 的「度数」区间查「星宿」。
  static String? matchTwentyEightStarLayer({
    required double sittingDegree,
    required double facingDialDegree,
    required dynamic root,
  }) {
    final list = _listForLayer(root, '二十八星宿');
    if (list == null) return null;
    final xiang = _lookupStarMansion(facingDialDegree, list);
    final zuo = _lookupStarMansion(sittingDegree, list);
    if (xiang == null && zuo == null) return null;
    return '向:${xiang ?? '—'}  坐:${zuo ?? '—'}';
  }

  static List<dynamic>? _listForLayer(dynamic root, String layerName) {
    if (root is List) return root;
    if (root is Map) {
      final map = Map<String, dynamic>.from(root);
      final direct = map[layerName];
      if (direct is List) return direct;
      final lists = map.values.whereType<List>().toList();
      if (lists.length == 1) return lists.first;
    }
    return null;
  }

  static String? _lookupStarMansion(double degree, List<dynamic> list) {
    final h = _normDeg(degree);
    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final range = m['度数']?.toString();
      if (range == null || range.isEmpty) continue;
      if (_inSeatRange(h, range)) {
        final star = m['星宿'];
        return star is String ? star : star?.toString();
      }
    }
    return null;
  }

  static bool _useSittingSideForRange(Map<String, dynamic> m) {
    if (m.containsKey('坐方度数')) return true;
    if (m['坐'] is String && m['向'] is String) return true;
    if (m['后天八卦_卦位'] is Map ||
        m['先天八卦_卦位'] is Map ||
        m['先天八卦洛书数'] is Map) {
      return true;
    }
    return false;
  }

  static Map<String, dynamic>? _scanListData(
    double sittingDegree,
    double facingDialDegree,
    List<dynamic> list,
  ) {
    for (final e in list) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e as Map);
      final range = (m['坐方度数'] ?? m['度数'])?.toString();
      if (range == null || range.isEmpty) continue;
      final h = _normDeg(
        _useSittingSideForRange(m) ? sittingDegree : facingDialDegree,
      );
      if (_inSeatRange(h, range)) {
        return m;
      }
    }
    return null;
  }

  static double _normDeg(double d) {
    double h = d % 360;
    if (h < 0) h += 360;
    return h;
  }

  static bool _inSeatRange(double h, String range) {
    h = _normDeg(h);
    final parts = range.split('-');
    if (parts.length != 2) return false;
    final lo = double.tryParse(parts[0].trim());
    final hi = double.tryParse(parts[1].trim());
    if (lo == null || hi == null) return false;
    const eps = 1e-9;
    if (hi.abs() < eps && lo > 90) {
      return h + eps >= lo;
    }
    if (lo > hi + eps) {
      return h + eps >= lo || h < hi + eps;
    }
    return h + eps >= lo && h < hi + eps;
  }

  /// [layerName] 为 JSON 文件名（无扩展名），八卦三类数据相同但按文件名取对应字段。
  static String _formatMatchedRow(Map<String, dynamic> m, {String? layerName}) {
    if (layerName != null) {
      final nested = m[layerName];
      if (nested is Map) {
        final zs = nested['坐'];
        final zx = nested['向'];
        if (zs is String && zx is String) {
          return '向:$zx 坐:$zs';
        }
      }
    }

    final zuo = m['坐'];
    final xiang = m['向'];
    if (zuo is String && xiang is String) {
      return '向:$xiang  坐:$zuo';
    }
    final star = m['星宿'];
    if (star is String) {
      return star;
    }
    return m.entries
        .where((e) => e.value is String && e.key != '坐方度数' && e.key != '度数')
        .take(4)
        .map((e) => '${e.key}:${e.value}')
        .join(' ');
  }
}

class DefaultTipJsonEntry {
  DefaultTipJsonEntry({
    required this.displayName,
    required this.root,
  });

  final String displayName;
  final dynamic root;

  String? resolve(
    double sittingDegree,
    double facingDialDegree, {
    String? compassFacing,
    String? compassSitting,
  }) {
    if (displayName == '地盘正针二十四山' &&
        compassFacing != null &&
        compassSitting != null) {
      return '向:$compassFacing  坐:$compassSitting';
    }
    if (displayName == '二十八星宿') {
      return DefaultTipJsonCatalog.matchTwentyEightStarLayer(
        sittingDegree: sittingDegree,
        facingDialDegree: facingDialDegree,
        root: root,
      );
    }
    return DefaultTipJsonCatalog.matchRow(
      sittingDegree: sittingDegree,
      facingDialDegree: facingDialDegree,
      root: root,
      layerName: displayName,
    );
  }
}
