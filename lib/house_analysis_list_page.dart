import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'auth_service.dart';
import 'house_analysis_result_page.dart';
import 'api_config.dart';

class HouseAnalysisListItem {
  HouseAnalysisListItem({
    required this.id,
    required this.houseName,
    required this.unitName,
    required this.period,
    required this.mountain,
    required this.direction,
    required this.selectedYear,
    required this.sittingText,
    required this.directionWithDegree,
    required this.createTime,
  });

  final int id;
  final String houseName;
  final String unitName;
  final int period;
  final String mountain;
  final String direction;
  final String selectedYear;
  final String sittingText;
  final String directionWithDegree;
  final String createTime;

  static int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }

  factory HouseAnalysisListItem.fromJson(Map<String, dynamic> json) {
    return HouseAnalysisListItem(
      id: _parseInt(json['id']),
      houseName: (json['houseName'] ?? '未命名房屋').toString(),
      unitName: (json['unitName'] ?? '').toString(),
      period: _parseInt(json['period']),
      mountain: (json['mountain'] ?? '').toString(),
      direction: (json['direction'] ?? '').toString(),
      selectedYear: (json['selectedYear'] ?? '').toString(),
      sittingText: (json['sittingText'] ?? '').toString(),
      directionWithDegree: (json['directionWithDegree'] ?? '').toString(),
      createTime: (json['createTime'] ?? '').toString(),
    );
  }
}

/// 房屋分析列表页：展示已保存的房屋分析记录，点击可重新加载并渲染结果页
class HouseAnalysisListPage extends StatefulWidget {
  const HouseAnalysisListPage({super.key});

  @override
  State<HouseAnalysisListPage> createState() => _HouseAnalysisListPageState();
}

class _HouseAnalysisListPageState extends State<HouseAnalysisListPage> {
  bool _loading = true;
  String? _error;
  List<HouseAnalysisListItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!AuthService.isLoggedIn) {
      setState(() {
        _loading = false;
        _error = '当前未登录';
        _items = [];
      });
      return;
    }

    final user = AuthService.currentUser.value;
    if (user == null) {
      setState(() {
        _loading = false;
        _error = '用户信息异常，请重新登录';
        _items = [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await http.get(
        Uri.parse('$kApiBaseUrl/cp/houseAnalysis/list?userId=${user.userId}'),
        headers: {
          'Authorization': 'Bearer ${user.token}',
        },
      );

      if (!mounted) return;

      if (resp.statusCode != 200) {
        setState(() {
          _loading = false;
          _error = '加载失败，状态码：${resp.statusCode}';
        });
        return;
      }

      final data = json.decode(resp.body);
      if (data is! Map || (data['code'] != 200 && data['code'] != '200')) {
        setState(() {
          _loading = false;
          _error = '加载失败：${(data is Map ? data['msg'] : null) ?? '未知错误'}';
        });
        return;
      }

      final list = (data['data'] as List?) ?? [];
      final items = list
          .map((e) => HouseAnalysisListItem.fromJson(
                e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e),
              ))
          .toList();

      setState(() {
        _loading = false;
        _items = items;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '加载异常：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '分析列表',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      TextButton(onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Text(
                                '暂无已保存的分析结果',
                                style: TextStyle(color: Colors.black54),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final it = _items[index];
                            return InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                _showItemActionDialog(it);
                              },
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.06),
                                      blurRadius: 10,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            it.houseName.isEmpty
                                                ? '未命名房屋'
                                                : it.houseName,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.black87,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          it.createTime,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black45,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (it.unitName.trim().isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text(
                                        it.unitName,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.black54,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Text(
                                      '${it.sittingText}  ${it.directionWithDegree}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${it.selectedYear} · ${it.period}运',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }

  /// 列表项点击后弹出“查看 / 删除”弹窗
  void _showItemActionDialog(HouseAnalysisListItem it) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '请选择操作',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  it.houseName.isEmpty ? '未命名房屋' : it.houseName,
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop(); // 关闭弹窗
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => HouseAnalysisResultPage(
                                sittingDirectionText: it.sittingText,
                                directionWithDegree: it.directionWithDegree,
                                selectedYear: it.selectedYear,
                                mountain: it.mountain,
                                direction: it.direction,
                                analysisId: it.id,
                                initialHouseName: it.houseName,
                                initialUnitName: it.unitName,
                              ),
                            ),
                          );
                        },
                        child: const Text('查看'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop(); // 关闭当前弹窗
                          _confirmDelete(it);
                        },
                        child: const Text('删除'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 删除前确认
  void _confirmDelete(HouseAnalysisListItem it) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('确认删除'),
          content: Text(
            '确定要删除该房屋分析结果吗？\n${it.houseName.isEmpty ? '未命名房屋' : it.houseName}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop(); // 关闭确认框
                await _deleteItem(it);
              },
              child: const Text(
                '删除',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 调用后端接口删除记录
  Future<void> _deleteItem(HouseAnalysisListItem it) async {
    final user = AuthService.currentUser.value;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前未登录，无法删除')),
      );
      return;
    }
    try {
      final resp = await http.delete(
        Uri.parse('$kApiBaseUrl/cp/houseAnalysis/${it.id}?userId=${user.userId}'),
        headers: {
          'Authorization': 'Bearer ${user.token}',
        },
      );
      if (!mounted) return;
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data is Map && (data['code'] == 200 || data['code'] == '200')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('删除成功')),
          );
          await _load();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('删除失败：${data['msg'] ?? '未知错误'}'),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败，状态码：${resp.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除异常：$e')),
      );
    }
  }
}

