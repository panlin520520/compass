import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'api_config.dart';
import 'compass_display_page.dart';

class CpMeasureRecordModel {
  final int id;
  final int? userId;
  final String compassName;
  final String compassAsset;
  final String compassImageUrl;
  final double? sittingDegree;
  final double? facingDegree;
  final String sittingText;
  final String facingText;
  final String sittingDetail;
  final String facingDetail;
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final String address;
  final DateTime? measureTime;
  final String lunarText;
  final String remarkText;

  CpMeasureRecordModel({
    required this.id,
    required this.userId,
    required this.compassName,
    required this.compassAsset,
    required this.compassImageUrl,
    required this.sittingDegree,
    required this.facingDegree,
    required this.sittingText,
    required this.facingText,
    required this.sittingDetail,
    required this.facingDetail,
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.address,
    required this.measureTime,
    required this.lunarText,
    required this.remarkText,
  });

  /// 用于列表/详情展示的罗盘图路径（优先 compass_image，其次 compass_asset）
  String? get displayCompassAssetPath {
    final img = compassImageUrl.trim();
    if (img.isNotEmpty && !_looksLikeLegacyBase64(img)) {
      return img;
    }
    final asset = compassAsset.trim();
    if (asset.isNotEmpty) {
      return asset;
    }
    return null;
  }

  /// 旧版 BLOB/base64 数据（迁移前记录）
  bool get hasLegacyBase64Image {
    final img = compassImageUrl.trim();
    return img.isNotEmpty && _looksLikeLegacyBase64(img);
  }

  static bool _looksLikeLegacyBase64(String s) {
    if (s.startsWith('http://') || s.startsWith('https://')) return false;
    if (s.startsWith('assets/') || s.startsWith('app-assets/')) return false;
    if (s.length < 80) return false;
    return RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(s);
  }

  static CpMeasureRecordModel fromJson(Map<String, dynamic> m) {
    DateTime? parseTime(dynamic v) {
      if (v == null) return null;
      final s = v.toString();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s.replaceFirst(' ', 'T'));
    }

    double? parseDouble(dynamic v) {
      if (v == null) return null;
      return double.tryParse(v.toString());
    }

    int? parseInt(dynamic v) {
      if (v == null) return null;
      return int.tryParse(v.toString());
    }

    return CpMeasureRecordModel(
      id: int.parse(m['id'].toString()),
      userId: parseInt(m['userId']),
      compassName: (m['compassName'] ?? '').toString(),
      compassAsset: (m['compassAsset'] ?? '').toString(),
      compassImageUrl: (m['compassImage'] ?? '').toString(),
      sittingDegree: parseDouble(m['sittingDegree']),
      facingDegree: parseDouble(m['facingDegree']),
      sittingText: (m['sittingText'] ?? '').toString(),
      facingText: (m['facingText'] ?? '').toString(),
      sittingDetail: (m['sittingDetail'] ?? '').toString(),
      facingDetail: (m['facingDetail'] ?? '').toString(),
      latitude: parseDouble(m['latitude']),
      longitude: parseDouble(m['longitude']),
      altitude: parseDouble(m['altitude']),
      address: (m['address'] ?? '').toString(),
      measureTime: parseTime(m['measureTime']),
      lunarText: (m['lunarText'] ?? '').toString(),
      remarkText: (m['remarkText'] ?? '').toString(),
    );
  }

  CpMeasureRecordModel copyWith({
    String? compassName,
    String? sittingText,
    String? facingText,
    String? sittingDetail,
    String? facingDetail,
    double? sittingDegree,
    double? facingDegree,
    double? latitude,
    double? longitude,
    double? altitude,
    String? address,
    DateTime? measureTime,
    String? lunarText,
    String? remarkText,
  }) {
    return CpMeasureRecordModel(
      id: id,
      userId: userId,
      compassName: compassName ?? this.compassName,
      compassAsset: compassAsset,
      compassImageUrl: compassImageUrl,
      sittingDegree: sittingDegree ?? this.sittingDegree,
      facingDegree: facingDegree ?? this.facingDegree,
      sittingText: sittingText ?? this.sittingText,
      facingText: facingText ?? this.facingText,
      sittingDetail: sittingDetail ?? this.sittingDetail,
      facingDetail: facingDetail ?? this.facingDetail,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      address: address ?? this.address,
      measureTime: measureTime ?? this.measureTime,
      lunarText: lunarText ?? this.lunarText,
      remarkText: remarkText ?? this.remarkText,
    );
  }

  /// 提交更新接口用的 JSON（不修改罗盘图片 URL）
  Map<String, dynamic> toUpdateJson() {
    String? formatMeasureTime() {
      final t = measureTime;
      if (t == null) return null;
      final y = t.year.toString().padLeft(4, '0');
      final mo = t.month.toString().padLeft(2, '0');
      final d = t.day.toString().padLeft(2, '0');
      final h = t.hour.toString().padLeft(2, '0');
      final mi = t.minute.toString().padLeft(2, '0');
      final s = t.second.toString().padLeft(2, '0');
      return '$y-$mo-$d $h:$mi:$s';
    }

    return {
      'id': id,
      'userId': userId,
      'compassName': compassName,
      'sittingDegree': sittingDegree,
      'facingDegree': facingDegree,
      'sittingText': sittingText,
      'facingText': facingText,
      'sittingDetail': sittingDetail,
      'facingDetail': facingDetail,
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'address': address,
      'measureTime': formatMeasureTime(),
      'lunarText': lunarText,
      'remarkText': remarkText,
    };
  }
}

class MeasureRecordListPage extends StatefulWidget {
  final String baseUrl;
  const MeasureRecordListPage({super.key, required this.baseUrl});

  @override
  State<MeasureRecordListPage> createState() => _MeasureRecordListPageState();
}

class _MeasureRecordListPageState extends State<MeasureRecordListPage> {
  bool _loading = true;
  String? _error;
  List<CpMeasureRecordModel> _all = [];

  int? _selectedYear;
  int? _selectedMonth;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final user = AuthService.currentUser.value;
    if (user == null || user.userId == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '未登录';
      });
      return;
    }

    try {
      final uri = Uri.parse(
          '${widget.baseUrl}/cp/measureRecord/list?userId=${user.userId}');
      final resp = await http.get(
        uri,
        headers: {
          if (user.token.isNotEmpty) 'Authorization': 'Bearer ${user.token}',
        },
      );
      if (!mounted) return;
      final Map<String, dynamic> json =
          jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode != 200 || json['code'] != 200) {
        throw Exception(json['msg']?.toString() ?? '加载失败');
      }
      final data = (json['data'] as List).cast<dynamic>();
      final list = data
          .map((e) => CpMeasureRecordModel.fromJson(e as Map<String, dynamic>))
          .toList();

      int? year;
      if (list.isNotEmpty && list.first.measureTime != null) {
        year = list.first.measureTime!.year;
      }

      if (!mounted) return;
      setState(() {
        _all = list;
        _selectedYear = year;
        _selectedMonth = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  List<int> get _years {
    final ys = <int>{};
    for (final r in _all) {
      final t = r.measureTime;
      if (t != null) ys.add(t.year);
    }
    final list = ys.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  List<CpMeasureRecordModel> get _filtered {
    return _all.where((r) {
      final t = r.measureTime;
      if (t == null) return true;
      if (_selectedYear != null && t.year != _selectedYear) return false;
      if (_selectedMonth != null && t.month != _selectedMonth) return false;
      return true;
    }).toList();
  }

  Future<void> _deleteRecord(CpMeasureRecordModel r) async {
    final user = AuthService.currentUser.value;
    if (user == null || user.userId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('未登录，无法删除')));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('删除记录'),
          content: const Text('确定要删除这条测量记录吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirm != true) return;

    try {
      final uri = Uri.parse(
          '${widget.baseUrl}/cp/measureRecord/${r.id}?userId=${user.userId}');
      final resp = await http.delete(
        uri,
        headers: {
          if (user.token.isNotEmpty) 'Authorization': 'Bearer ${user.token}',
        },
      );
      final Map<String, dynamic> json =
          jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode != 200 || json['code'] != 200) {
        throw Exception(json['msg']?.toString() ?? '删除失败');
      }
      if (!mounted) return;
      setState(() {
        _all.removeWhere((e) => e.id == r.id);
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('删除成功')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除失败: $e')));
    }
  }

  String _titleLine(CpMeasureRecordModel r) {
    final detail = r.facingDetail.isNotEmpty ? r.facingDetail : r.sittingDetail;
    final deg = r.facingDegree?.toStringAsFixed(1);
    final facing = r.facingText.isNotEmpty ? r.facingText : '';
    final degreePart = deg != null ? '$deg°' : '';
    return detail.isNotEmpty
        ? '$detail ${facing.isNotEmpty ? facing.replaceAll(RegExp(r'\\d+\\.?\\d*°'), '') : ''}$degreePart'
        : '${r.sittingText} ${r.facingText}';
  }

  String _timeRight(CpMeasureRecordModel r) {
    final t = r.measureTime;
    if (t == null) return '';
    final day = t.day;
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$day日$hh:$mm';
  }

  Widget? _buildListThumb(CpMeasureRecordModel r) {
    final path = r.displayCompassAssetPath;
    if (path != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: AppAssetImage(
          assetPath: path,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
    }
    if (r.hasLegacyBase64Image) {
      try {
        final bytes = base64Decode(r.compassImageUrl);
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.memory(
            bytes,
            width: 44,
            height: 44,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('罗盘测量记录'),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        surfaceTintColor: Colors.transparent,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                DropdownButton<int>(
                  value: _selectedYear,
                  hint: const Text('年份'),
                  items: _years
                      .map((y) => DropdownMenuItem(
                            value: y,
                            child: Text('$y年'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedYear = v),
                ),
                const SizedBox(width: 24),
                DropdownButton<int?>(
                  value: _selectedMonth,
                  hint: const Text('月份不限'),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('月份不限'),
                    ),
                    ...List.generate(
                      12,
                      (i) => DropdownMenuItem<int?>(
                        value: i + 1,
                        child: Text('${i + 1}月'),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedMonth = v),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _filtered.isEmpty
                        ? const Center(child: Text('暂无记录'))
                        : ListView.separated(
                            itemCount: _filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, i) {
                              final r = _filtered[i];
                              final thumb = _buildListThumb(r);
                              return InkWell(
                                onTap: () async {
                                  final updated =
                                      await Navigator.push<CpMeasureRecordModel>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => MeasureRecordDetailPage(
                                        baseUrl: widget.baseUrl,
                                        recordId: r.id,
                                        initial: r,
                                      ),
                                    ),
                                  );
                                  if (updated != null && mounted) {
                                    setState(() {
                                      final i = _all
                                          .indexWhere((e) => e.id == updated.id);
                                      if (i >= 0) _all[i] = updated;
                                    });
                                  }
                                },
                                onLongPress: () async {
                                  final action =
                                      await showModalBottomSheet<String>(
                                    context: context,
                                    builder: (ctx) {
                                      return SafeArea(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ListTile(
                                              leading: const Icon(Icons.delete,
                                                  color: Colors.red),
                                              title: const Text('删除',
                                                  style: TextStyle(
                                                      color: Colors.red)),
                                              onTap: () =>
                                                  Navigator.of(ctx).pop('delete'),
                                            ),
                                            ListTile(
                                              leading: const Icon(Icons.close),
                                              title: const Text('取消'),
                                              onTap: () =>
                                                  Navigator.of(ctx).pop('cancel'),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                  if (action == 'delete') {
                                    await _deleteRecord(r);
                                  }
                                },
                                child: ListTile(
                                  leading: thumb,
                                  title: Text(
                                    _titleLine(r),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    r.address.isNotEmpty ? r.address : '未知地点',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  trailing: Text(
                                    _timeRight(r),
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class MeasureRecordDetailPage extends StatefulWidget {
  final String baseUrl;
  final int recordId;
  final CpMeasureRecordModel? initial;

  const MeasureRecordDetailPage({
    super.key,
    required this.baseUrl,
    required this.recordId,
    this.initial,
  });

  @override
  State<MeasureRecordDetailPage> createState() => _MeasureRecordDetailPageState();
}

class _MeasureRecordDetailPageState extends State<MeasureRecordDetailPage> {
  bool _loading = true;
  String? _error;
  CpMeasureRecordModel? _record;

  @override
  void initState() {
    super.initState();
    _record = widget.initial;
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final user = AuthService.currentUser.value;
    try {
      final uri =
          Uri.parse('${widget.baseUrl}/cp/measureRecord/${widget.recordId}');
      final resp = await http.get(
        uri,
        headers: {
          if (user != null && user.token.isNotEmpty)
            'Authorization': 'Bearer ${user.token}',
        },
      );
      if (!mounted) return;
      final Map<String, dynamic> json =
          jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode != 200 || json['code'] != 200) {
        throw Exception(json['msg']?.toString() ?? '加载失败');
      }
      final data = json['data'] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _record = CpMeasureRecordModel.fromJson(data);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _openEdit(CpMeasureRecordModel r) async {
    final updated = await Navigator.push<CpMeasureRecordModel>(
      context,
      MaterialPageRoute(
        builder: (_) => MeasureRecordEditPage(
          baseUrl: widget.baseUrl,
          record: r,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _record = updated);
    }
  }

  void _openCompassDisplay(CpMeasureRecordModel r) {
    final path = r.displayCompassAssetPath;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CompassDisplayPage(
          compassImageUrl: path,
          compassImageBase64:
              r.hasLegacyBase64Image ? r.compassImageUrl : '',
          sittingText: r.sittingText,
          facingText: r.facingText,
          sittingDetail: r.sittingDetail,
          facingDetail: r.facingDetail,
          sittingDegree: r.sittingDegree,
          facingDegree: r.facingDegree,
          address: r.address,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('测量记录'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, _record),
        ),
        automaticallyImplyLeading: false,
        actions: [
          if (_record != null && !_loading && _error == null)
            TextButton(
              onPressed: () => _openEdit(_record!),
              child: const Text(
                '编辑',
                style: TextStyle(fontSize: 16),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _record == null
                  ? const Center(child: Text('记录不存在'))
                  : _buildBody(_record!),
    );
  }

  Widget _buildBody(CpMeasureRecordModel r) {
    String coord() {
      if (r.latitude == null || r.longitude == null) return '--';
      return '东经${r.longitude!.toStringAsFixed(6)}  北纬${r.latitude!.toStringAsFixed(6)}';
    }

    String timeText() {
      final t = r.measureTime;
      if (t == null) return '';
      return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }

    Widget card(String label, String value) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 92,
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: Text(value)),
          ],
        ),
      );
    }

    Widget compassRow() {
      Widget? thumb;
      final imagePath = r.displayCompassAssetPath;
      if (imagePath != null) {
        thumb = GestureDetector(
          onTap: () => _openCompassDisplay(r),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: AppAssetImage(
              assetPath: imagePath,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        );
      } else if (r.hasLegacyBase64Image) {
        try {
          final bytes = base64Decode(r.compassImageUrl);
          thumb = GestureDetector(
            onTap: () => _openCompassDisplay(r),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.memory(
                bytes,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
              ),
            ),
          );
        } catch (_) {
          thumb = null;
        }
      }

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(
              width: 92,
              child: Text(
                '测量罗盘',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(child: Text(r.compassName)),
            if (thumb != null) ...[
              const SizedBox(width: 8),
              thumb,
            ],
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          compassRow(),
          card('坐', r.sittingText),
          card('向', r.facingText),
          card('坐', r.sittingDetail),
          card('向', r.facingDetail),
          card('测量时间', timeText()),
          if (r.lunarText.isNotEmpty) card('农历', r.lunarText),
          card('测量地点', r.address.isNotEmpty ? r.address : '--'),
          card('经纬度', coord()),
          card('海拔',
              r.altitude != null ? '${r.altitude!.toStringAsFixed(0)}米' : '--'),
          if (r.remarkText.isNotEmpty) card('备注', r.remarkText),
        ],
      ),
    );
  }
}

/// 编辑测量记录
class MeasureRecordEditPage extends StatefulWidget {
  final String baseUrl;
  final CpMeasureRecordModel record;

  const MeasureRecordEditPage({
    super.key,
    required this.baseUrl,
    required this.record,
  });

  @override
  State<MeasureRecordEditPage> createState() => _MeasureRecordEditPageState();
}

class _MeasureRecordEditPageState extends State<MeasureRecordEditPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _compassNameCtrl;
  late final TextEditingController _sittingTextCtrl;
  late final TextEditingController _facingTextCtrl;
  late final TextEditingController _sittingDetailCtrl;
  late final TextEditingController _facingDetailCtrl;
  late final TextEditingController _sittingDegreeCtrl;
  late final TextEditingController _facingDegreeCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _lunarTextCtrl;
  late final TextEditingController _remarkTextCtrl;
  late final TextEditingController _altitudeCtrl;
  late final TextEditingController _measureTimeCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    _compassNameCtrl = TextEditingController(text: r.compassName);
    _sittingTextCtrl = TextEditingController(text: r.sittingText);
    _facingTextCtrl = TextEditingController(text: r.facingText);
    _sittingDetailCtrl = TextEditingController(text: r.sittingDetail);
    _facingDetailCtrl = TextEditingController(text: r.facingDetail);
    _sittingDegreeCtrl = TextEditingController(
      text: r.sittingDegree?.toStringAsFixed(1) ?? '',
    );
    _facingDegreeCtrl = TextEditingController(
      text: r.facingDegree?.toStringAsFixed(1) ?? '',
    );
    _addressCtrl = TextEditingController(text: r.address);
    _lunarTextCtrl = TextEditingController(text: r.lunarText);
    _remarkTextCtrl = TextEditingController(text: r.remarkText);
    _altitudeCtrl = TextEditingController(
      text: r.altitude != null ? r.altitude!.toStringAsFixed(0) : '',
    );
    final t = r.measureTime;
    _measureTimeCtrl = TextEditingController(
      text: t == null
          ? ''
          : '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
              '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
    );
  }

  @override
  void dispose() {
    _compassNameCtrl.dispose();
    _sittingTextCtrl.dispose();
    _facingTextCtrl.dispose();
    _sittingDetailCtrl.dispose();
    _facingDetailCtrl.dispose();
    _sittingDegreeCtrl.dispose();
    _facingDegreeCtrl.dispose();
    _addressCtrl.dispose();
    _lunarTextCtrl.dispose();
    _remarkTextCtrl.dispose();
    _altitudeCtrl.dispose();
    _measureTimeCtrl.dispose();
    super.dispose();
  }

  double? _parseOptionalDouble(String s) {
    final v = s.trim();
    if (v.isEmpty) return null;
    return double.tryParse(v);
  }

  DateTime? _parseMeasureTime(String s) {
    final v = s.trim();
    if (v.isEmpty) return widget.record.measureTime;
    final normalized = v.contains('T') ? v : v.replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized) ??
        DateTime.tryParse(v.replaceFirst(' ', 'T'));
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
    String? hint,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final user = AuthService.currentUser.value;
    if (user == null || user.userId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('未登录，无法保存')));
      return;
    }

    setState(() => _saving = true);

    final updated = widget.record.copyWith(
      compassName: _compassNameCtrl.text.trim(),
      sittingText: _sittingTextCtrl.text.trim(),
      facingText: _facingTextCtrl.text.trim(),
      sittingDetail: _sittingDetailCtrl.text.trim(),
      facingDetail: _facingDetailCtrl.text.trim(),
      sittingDegree: _parseOptionalDouble(_sittingDegreeCtrl.text),
      facingDegree: _parseOptionalDouble(_facingDegreeCtrl.text),
      address: _addressCtrl.text.trim(),
      lunarText: _lunarTextCtrl.text.trim(),
      remarkText: _remarkTextCtrl.text.trim(),
      altitude: _parseOptionalDouble(_altitudeCtrl.text),
      measureTime: _parseMeasureTime(_measureTimeCtrl.text),
    );

    try {
      final resp = await http.post(
        Uri.parse('${widget.baseUrl}/cp/measureRecord/update'),
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          if (user.token.isNotEmpty) 'Authorization': 'Bearer ${user.token}',
        },
        body: jsonEncode(updated.toUpdateJson()),
      );

      if (!mounted) return;

      final Map<String, dynamic> json =
          jsonDecode(resp.body) as Map<String, dynamic>;
      final ok = resp.statusCode == 200 && (json['code'] == 200 || json['code'] == '200');

      if (ok) {
        final data = json['data'] as Map<String, dynamic>?;
        final model = data != null
            ? CpMeasureRecordModel.fromJson(data)
            : updated;
        if (!mounted) return;
        Navigator.pop(context, model);
      } else {
        throw Exception(json['msg']?.toString() ?? '保存失败');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('编辑测量记录'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field(label: '测量罗盘', controller: _compassNameCtrl),
            _field(label: '坐（文本）', controller: _sittingTextCtrl),
            _field(label: '向（文本）', controller: _facingTextCtrl),
            _field(label: '坐（山向）', controller: _sittingDetailCtrl),
            _field(label: '向（山向）', controller: _facingDetailCtrl),
            _field(
              label: '坐向度数',
              controller: _sittingDegreeCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            _field(
              label: '朝向度数',
              controller: _facingDegreeCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            _field(
              label: '测量时间',
              controller: _measureTimeCtrl,
              hint: '例如 2026-05-27 14:30',
            ),
            _field(label: '农历', controller: _lunarTextCtrl),
            _field(
              label: '测量地点',
              controller: _addressCtrl,
              maxLines: 2,
            ),
            _field(
              label: '海拔（米）',
              controller: _altitudeCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            _field(
              label: '备注',
              controller: _remarkTextCtrl,
              maxLines: 3,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
