import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'auth_service.dart';
import 'house_analysis_api.dart';
import 'house_analysis_list_page.dart';
import 'api_config.dart';

/// 宫位在 3x3 网格中的显示顺序：第一排 4,9,2 第二排 3,5,7 第三排 8,1,6
const List<int> _gongNumOrder = [4, 9, 2, 3, 5, 7, 8, 1, 6];

/// 房屋分析结果页：展示坐向、年份、飞星盘、八宅、流年等
class HouseAnalysisResultPage extends StatefulWidget {
  const HouseAnalysisResultPage({
    super.key,
    required this.sittingDirectionText,
    required this.directionWithDegree,
    required this.selectedYear,
    required this.mountain,
    required this.direction,
    this.analysisId,
    this.initialHouseName,
    this.initialUnitName,
  });

  final String sittingDirectionText;
  final String directionWithDegree;
  final String selectedYear;
  /// 坐（如：子、戌）
  final String mountain;
  /// 向（如：午、辰）
  final String direction;
  /// 若从“分析列表”进入，则带上已保存记录的ID，用于修改/删除
  final int? analysisId;
  /// 初始房屋名称（从列表进入时填充）
  final String? initialHouseName;
  /// 初始单元名称（从列表进入时填充）
  final String? initialUnitName;

  @override
  State<HouseAnalysisResultPage> createState() =>
      _HouseAnalysisResultPageState();
}

class _HouseAnalysisResultPageState extends State<HouseAnalysisResultPage> {
  late final TextEditingController _houseNameController;
  late final TextEditingController _unitNameController;

  HouseAnalysisResponse? _data;
  bool _loading = true;
  String? _error;
  bool _showTigua = false; // 是否显示替卦

  /// 从 selectedYear 解析运数 1-9
  int get _period {
    const map = {
      '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
      '六': 6, '七': 7, '八': 8, '九': 9,
    };
    final m = RegExp(r'\(([一二三四五六七八九])运\)').firstMatch(widget.selectedYear);
    return m != null ? (map[m.group(1)!] ?? 9) : 9;
  }

  @override
  void initState() {
    super.initState();
    _houseNameController = TextEditingController(
      text: (widget.initialHouseName == null || widget.initialHouseName!.isEmpty)
          ? '房屋名称'
          : widget.initialHouseName,
    );
    _unitNameController = TextEditingController(
      text: (widget.initialUnitName == null || widget.initialUnitName!.isEmpty)
          ? '单元名称'
          : widget.initialUnitName,
    );
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await fetchHouseAnalysis(
      period: _period,
      mountain: widget.mountain,
      direction: widget.direction,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res == null) {
        _error = '加载失败，请稍后重试';
      } else {
        _data = res;
      }
    });
  }

  @override
  void dispose() {
    _houseNameController.dispose();
    _unitNameController.dispose();
    super.dispose();
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
          '房屋分析',
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
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: _loadData,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildBasicInfo(),
                      _buildUnifiedGrid(),
                      _buildYunSittingSection(),
                      // _buildCalculationResults(),
                      _buildEightMansionsSection(),
                      _buildLiuNianSection(),
                      _buildSaveButton(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildBasicInfo() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoRow('房屋', _houseNameController),
          const SizedBox(height: 12),
          _buildInfoRow('单元', _unitNameController),
          const SizedBox(height: 12),
          _buildInfoRow('坐向',
              '${widget.sittingDirectionText} (${widget.directionWithDegree})'),
          const SizedBox(height: 12),
          _buildInfoRow('年份', widget.selectedYear),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, dynamic value) {
    if (value is TextEditingController) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: value,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value as String,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
      ],
    );
  }

  /// 按 gongNum 顺序取项
  T? _itemByGongNum<T>(List<T> list, int gongNum, int Function(T) getGongNum) {
    try {
      return list.firstWhere((e) => getGongNum(e) == gongNum);
    } catch (e) {
      // 如果找不到，返回null
      return null;
    }
  }

  /// 玄空飞星 + 八宅 + 流年 统一矩阵：每格左上角山向数、中间左运盘、中间右流年、底部八宅
  Widget _buildUnifiedGrid() {
    final xk = _data!.xuanKongFeiXing;
    final eight = _data!.eightMansionsCompass;
    final liu = _data!.liuNian;
    
    // 调试：打印数据
    print('xuanKongFeiXing 数据: ${xk.map((e) => 'gongNum=${e.gongNum}, mountainNum=${e.mountainNum}, waterNum=${e.waterNum}').join('; ')}');
    print('_gongNumOrder: $_gongNumOrder');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOrientationFrame((size) => _buildUnifiedGridContent(size, xk, eight, liu)),
        ],
      ),
    );
  }

  /// 将数字转换为中文数字（1-9）
  String _numberToChinese(int? num) {
    if (num == null || num < 1 || num > 9) return '';
    const map = {
      1: '一', 2: '二', 3: '三', 4: '四', 5: '五',
      6: '六', 7: '七', 8: '八', 9: '九',
    };
    return map[num] ?? '';
  }

  /// 从流年star中提取数字（如"一白贪狼" -> "一"）
  String _extractNumberFromStar(String? star) {
    if (star == null || star.isEmpty) return '';
    // 提取第一个中文字符（已经是中文数字）
    if (star.isNotEmpty) {
      final firstChar = star[0];
      // 检查是否是中文数字
      const chineseNumbers = ['一', '二', '三', '四', '五', '六', '七', '八', '九'];
      if (chineseNumbers.contains(firstChar)) {
        return firstChar;
      }
    }
    return '';
  }

  /// 八宅 luck 含「吉」则为吉位
  bool _isLuckJi(String? luck) => luck != null && luck.contains('吉');

  /// 玄空飞星数字底色（格子右侧流年数等）
  Color _flyingStarNumberBgColor(String chineseNum) {
    switch (chineseNum) {
      case '九':
        return const Color(0xFF9C27B0); // 紫
      case '五':
        return const Color(0xFFFFEB3B); // 黄
      case '七':
        return const Color(0xFFE53935); // 红
      case '八':
      case '一':
      case '六':
        return Colors.white;
      case '三':
        return const Color(0xFF69F0AE); // 亮绿
      case '四':
        return const Color(0xFF1B5E20); // 深绿
      case '二':
        return Colors.black;
      default:
        return Colors.transparent;
    }
  }

  Color _flyingStarNumberTextColor(String chineseNum) {
    switch (chineseNum) {
      case '二':
      case '四':
      case '九':
      case '七':
        return Colors.white;
      case '五':
      case '三':
        return Colors.black87;
      default:
        return Colors.black87;
    }
  }

  Widget _buildFlyingStarNumberBadge(String chineseNum, {double fontSize = 16}) {
    if (chineseNum.isEmpty) return const SizedBox.shrink();
    final bg = _flyingStarNumberBgColor(chineseNum);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        border: (chineseNum == '八' || chineseNum == '一' || chineseNum == '六')
            ? Border.all(color: Colors.grey.shade400)
            : null,
      ),
      child: Text(
        chineseNum,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: _flyingStarNumberTextColor(chineseNum),
        ),
      ),
    );
  }

  /// 流年格内星名标签（按星数铺底色，如九紫→紫底白字）
  Widget _buildLiuNianStarBadge(String starPrefix, {double fontSize = 13}) {
    if (starPrefix.isEmpty) return const SizedBox.shrink();
    final chineseNum = starPrefix.substring(0, 1);
    final bg = _flyingStarNumberBgColor(chineseNum);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        border: (chineseNum == '八' || chineseNum == '一' || chineseNum == '六')
            ? Border.all(color: Colors.grey.shade400)
            : null,
      ),
      child: Text(
        starPrefix,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
          color: _flyingStarNumberTextColor(chineseNum),
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildUnifiedGridContent(
    double size,
    List<XuanKongFeiXingItem> xk,
    List<EightMansionsItem> eight,
    List<LiuNianItem> liu,
  ) {
    return SizedBox(
      width: size,
      height: size,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: 9,
        itemBuilder: (context, i) {
          final gongNum = _gongNumOrder[i];
          final xkItem = _itemByGongNum(xk, gongNum, (e) => e.gongNum);
          final eightItem = _itemByGongNum(eight, gongNum, (e) => e.gongNum);
          final liuItem = _itemByGongNum(liu, gongNum, (e) => e.gongNum);
          
          // 调试：打印每个格子的信息
          final row = i ~/ 3; // 行号（0, 1, 2）
          final col = i % 3;  // 列号（0, 1, 2）
          print('格子[行${row+1},列${col+1}] (索引$i): gongNum=$gongNum, xkItem.gongNum=${xkItem?.gongNum}, mountainNum=${xkItem?.mountainNum}, waterNum=${xkItem?.waterNum}');
          
          // 提取流年数字
          final liuNianNum = _extractNumberFromStar(liuItem?.star);
          final isJi = _isLuckJi(eightItem?.luck);

          return Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isJi ? const Color(0xFFFCE4EC) : Colors.grey.shade100,
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 左上角和右上角：山数和向数
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      xkItem?.mountainNum.toString() ?? '',
                      style: const TextStyle(fontSize: 10, color: Colors.black54),
                    ),
                    Text(
                      xkItem?.waterNum.toString() ?? '',
                      style: const TextStyle(fontSize: 10, color: Colors.black54),
                    ),
                  ],
                ),
                // 中间：运盘数与流年数紧挨居中（右侧带飞星底色）
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        _numberToChinese(xkItem?.yunNum) ?? '',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 2),
                      _buildFlyingStarNumberBadge(liuNianNum),
                    ],
                  ),
                ),
                // 底部：八宅star
                Text(
                  eightItem?.star ?? '',
                  style: const TextStyle(fontSize: 10, color: Colors.black87),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String get _yunLabel {
    final s = widget.selectedYear;
    final match = RegExp(r'\(([一二三四五六七八九])运\)').firstMatch(s);
    if (match != null) return '${match.group(1)!}运${widget.sittingDirectionText}';
    return widget.sittingDirectionText;
  }

  Widget _buildYunSittingSection() {
    // 根据复选框状态决定显示哪个数据：未选中显示正常数据，选中显示替卦数据
    final displayData = _showTigua 
        ? (_data?.xuanKongFeiXingTigua ?? [])
        : (_data?.xuanKongFeiXing ?? []);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '玄空飞星',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _yunLabel,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: _showTigua,
                    onChanged: (v) {
                      setState(() {
                        _showTigua = v ?? false;
                      });
                    },
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const Text('兼卦', style: TextStyle(fontSize: 14)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildOrientationFrame((size) => _buildTiguaGrid(size, displayData)),
        ],
      ),
    );
  }

  Widget _buildTiguaGrid(double size, List<XuanKongFeiXingItem> tigua) {
    return SizedBox(
      width: size,
      height: size,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: 9,
        itemBuilder: (context, i) {
          final gongNum = _gongNumOrder[i];
          final item = _itemByGongNum(tigua, gongNum, (e) => e.gongNum);
          
          // 调试：打印替卦网格每个格子的信息
          final row = i ~/ 3;
          final col = i % 3;
          print('替卦网格[行${row+1},列${col+1}] (索引$i): gongNum=$gongNum, item.gongNum=${item?.gongNum}, mountainNum=${item?.mountainNum}, waterNum=${item?.waterNum}');
          return Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Text(
                      item?.mountainNum.toString() ?? '',
                      style: const TextStyle(fontSize: 10, color: Colors.red),
                    ),
                    Text(
                      item?.waterNum.toString() ?? '',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ],
                ),
                Text(
                  _numberToChinese(item?.yunNum) ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCalculationResults() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('计算结果显示以下盘局', showExplain: true),
          const SizedBox(height: 12),
          _resultItem('到山到向',
              '也称旺山旺向,是玄空风水的最佳格局,主丁财两旺。'),
          _resultItem('六运令星入囚', '地运年数160年。'),
          _resultItem('正城门丙',
              '城门诀法是当盘局不是旺山旺向时,通过求相某门旺气而达到旺丁旺财的目的。'),
        ],
      ),
    );
  }

  static const Color _explainButtonBorder = Color(0xFFD4A574);

  void _showExplainBottomSheet({required Widget content}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black54,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.8,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    '说明',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: content,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _explainButtonBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        '确定',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                        ),
                      ),
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

  Widget _explainLine(String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 14,
            color: Colors.black87,
            height: 1.45,
          ),
          children: [
            TextSpan(
              text: '$title: ',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            TextSpan(text: description),
          ],
        ),
      ),
    );
  }

  Widget _explainSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
    );
  }

  void _showEightMansionsExplainSheet() {
    _showExplainBottomSheet(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _explainSectionTitle('吉位'),
          _explainLine('伏位', '主吉，安静无为，可进可退，有利健康'),
          _explainLine('延年', '主长寿'),
          _explainLine('生气', '催官出富贵，大旺人丁'),
          _explainLine('天医', '主富贵福禄，仁慈好善'),
          const SizedBox(height: 8),
          _explainSectionTitle('凶位'),
          _explainLine('五鬼', '最凶位，位位相克，灾随位发，昂头即应'),
          _explainLine('六煞', '主淫荡，不利已婚人士'),
          _explainLine('绝命', '绝命者至凶之神，主疾病，死亡'),
          _explainLine('祸害', '主官非，疾病，散财，伤人口'),
        ],
      ),
    );
  }

  void _showLiuNianExplainSheet() {
    _showExplainBottomSheet(
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _explainLine('一白贪狼星', '桃花位, 利人缘, 爱情运'),
          _explainLine('二黑巨门星', '疾病位, 不利健康'),
          _explainLine('三碧禄存星', '是非位, 易有争吵, 官非'),
          _explainLine('四绿文曲星', '文昌位, 利学业, 文职工作人员'),
          _explainLine('五黄廉贞星', '灾祸位, 易有损伤, 不宜动土'),
          _explainLine('六白武曲星', '偏财位, 利娱乐, 艺术事业'),
          _explainLine('七赤破军星', '官非位, 利非文职, 纪律部队'),
          _explainLine('八白左辅星', '正财位'),
          _explainLine('九紫右弼星', '喜庆位, 利嫁娶, 添丁, 升官'),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, {bool showExplain = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        if (showExplain)
          TextButton(
            onPressed: () {},
            child: const Text('说明', style: TextStyle(fontSize: 14)),
          ),
      ],
    );
  }

  Widget _resultItem(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  static const double _orientationLabelWidth = 40;

  /// 二十四山 / 八方 → 洛书九宫格方位（与 _gongNumOrder 布局一致）
  static const Map<String, String> _shanToBaFang = {
    '子': '北',
    '癸': '北',
    '壬': '北',
    '亥': '北',
    '丑': '东北',
    '艮': '东北',
    '寅': '东北',
    '甲': '东',
    '卯': '东',
    '乙': '东',
    '辰': '东南',
    '巽': '东南',
    '巳': '东南',
    '丙': '南',
    '午': '南',
    '丁': '南',
    '未': '西南',
    '坤': '西南',
    '申': '西南',
    '庚': '西',
    '酉': '西',
    '辛': '西',
    '戌': '西北',
    '乾': '西北',
    '北': '北',
    '东北': '东北',
    '东': '东',
    '东南': '东南',
    '南': '南',
    '西南': '西南',
    '西': '西',
    '西北': '西北',
  };

  String _toBaFang(String shan) {
    final s = shan.trim();
    if (s.isEmpty) return '';
    return _shanToBaFang[s] ?? s;
  }

  /// 四正（东南西北）始终显示方位名；有坐/向时追加（坐）（向），如 北（向）
  /// 四角有坐/向时显示 东南（向）；无坐向时四角留空
  String _orientationSlotLabel(
    String baFang,
    String facingBaFang,
    String sittingBaFang, {
    bool isCorner = false,
  }) {
    final isFacing = baFang == facingBaFang;
    final isSitting = baFang == sittingBaFang;
    final suffix = StringBuffer();
    if (isFacing) suffix.write('（向）');
    if (isSitting) suffix.write('（坐）');
    if (suffix.isEmpty) {
      return isCorner ? '' : baFang;
    }
    return '$baFang$suffix';
  }

  Widget _orientationLabel(
    String text,
    TextStyle style, {
    int maxLines = 2,
  }) {
    return Text(
      text,
      style: style,
      textAlign: TextAlign.center,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 洛书九宫固定八方 + 根据坐/向标注 (坐)(向)
  /// 布局：上排 东南|南|西南，中排 东|盘|西，下排 东北|北|西北
  Widget _buildOrientationFrame(Widget Function(double gridSize) buildGrid) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gridSize =
            (constraints.maxWidth - 2 * _orientationLabelWidth).clamp(0.0, double.infinity);
        final labelStyle = const TextStyle(fontSize: 12, color: Colors.black87);
        final facingBaFang = _toBaFang(widget.direction);
        final sittingBaFang = _toBaFang(widget.mountain);
        String slot(String baFang, {bool isCorner = false}) =>
            _orientationSlotLabel(
              baFang,
              facingBaFang,
              sittingBaFang,
              isCorner: isCorner,
            );

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: _orientationLabelWidth,
                  child: _orientationLabel(slot('东南', isCorner: true), labelStyle),
                ),
                Expanded(
                  child: Center(
                    child: _orientationLabel(slot('南'), labelStyle),
                  ),
                ),
                SizedBox(
                  width: _orientationLabelWidth,
                  child: _orientationLabel(slot('西南', isCorner: true), labelStyle),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: _orientationLabelWidth,
                  height: gridSize,
                  child: Center(
                    child: _orientationLabel(slot('东'), labelStyle),
                  ),
                ),
                SizedBox(
                  width: gridSize,
                  height: gridSize,
                  child: buildGrid(gridSize),
                ),
                SizedBox(
                  width: _orientationLabelWidth,
                  height: gridSize,
                  child: Center(
                    child: _orientationLabel(slot('西'), labelStyle),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                SizedBox(
                  width: _orientationLabelWidth,
                  child: _orientationLabel(slot('东北', isCorner: true), labelStyle),
                ),
                Expanded(
                  child: Center(
                    child: _orientationLabel(slot('北'), labelStyle),
                  ),
                ),
                SizedBox(
                  width: _orientationLabelWidth,
                  child: _orientationLabel(slot('西北', isCorner: true), labelStyle),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// 八宅大游年部分
  Widget _buildEightMansionsSection() {
    final eight = _data!.eightMansionsCompass;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '八宅',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '八宅大游年',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              TextButton(
                onPressed: _showEightMansionsExplainSheet,
                child: const Text('说明', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildOrientationFrame((size) => _buildEightMansionsGrid(size, eight)),
        ],
      ),
    );
  }

  Widget _buildEightMansionsGrid(double size, List<EightMansionsItem> eight) {
    return SizedBox(
      width: size,
      height: size,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: 9,
        itemBuilder: (context, i) {
          final gongNum = _gongNumOrder[i];
          final item = _itemByGongNum(eight, gongNum, (e) => e.gongNum);
          final star = item?.star ?? '';
          final isJi = _isLuckJi(item?.luck);

          return Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isJi ? const Color(0xFFFCE4EC) : Colors.grey.shade200,
              border: Border.all(
                color: Colors.grey.shade300,
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                star,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: isJi ? Colors.black87 : Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      ),
    );
  }

  /// 流年部分
  Widget _buildLiuNianSection() {
    final liu = _data!.liuNian;
    // 获取当前年份，默认2026
    final currentYear = DateTime.now().year;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '流年',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '流年 ($currentYear):',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              TextButton(
                onPressed: _showLiuNianExplainSheet,
                child: const Text('说明', style: TextStyle(fontSize: 14)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildOrientationFrame((size) => _buildLiuNianGrid(size, liu)),
        ],
      ),
    );
  }

  Widget _buildLiuNianGrid(double size, List<LiuNianItem> liu) {
    // 从star中提取前两个字符（如"一白贪狼" -> "一白"）
    String getStarPrefix(String? star) {
      if (star == null || star.isEmpty) return '';
      return star.length >= 2 ? star.substring(0, 2) : star;
    }

    return SizedBox(
      width: size,
      height: size,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          childAspectRatio: 1,
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
        ),
        itemCount: 9,
        itemBuilder: (context, i) {
          final gongNum = _gongNumOrder[i];
          final item = _itemByGongNum(liu, gongNum, (e) => e.gongNum);
          final starPrefix = getStarPrefix(item?.star);
          final shensha = item?.shensha ?? '';

          return Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              border: Border.all(
                color: Colors.grey.shade300,
                width: 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (starPrefix.isNotEmpty)
                  _buildLiuNianStarBadge(starPrefix),
                if (shensha.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    shensha,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black87,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSaveButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: SizedBox(
        height: 50,
        child: ElevatedButton(
          onPressed: _onSavePressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            widget.analysisId != null ? '修改' : '保存分析结果',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
        ),
      ),
    );
  }

  /// 保存当前房屋分析结果到后端
  Future<void> _onSavePressed() async {
    final houseName = _houseNameController.text.trim().isEmpty
        ? '未命名房屋'
        : _houseNameController.text.trim();
    final unitName = _unitNameController.text.trim();

    if (!AuthService.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前未登录，无法保存分析结果')),
      );
      return;
    }

    final user = AuthService.currentUser.value;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('用户信息异常，请重新登录')),
      );
      return;
    }

    final bool isUpdate = widget.analysisId != null;

    final body = <String, dynamic>{
      if (isUpdate) 'id': widget.analysisId,
      'userId': user.userId,
      'houseName': houseName,
      'unitName': unitName,
      'period': _period,
      'mountain': widget.mountain,
      'direction': widget.direction,
      'selectedYear': widget.selectedYear,
      'sittingText': widget.sittingDirectionText,
      'directionWithDegree': widget.directionWithDegree,
    };

    try {
      final uri = isUpdate
          ? Uri.parse('$kApiBaseUrl/cp/houseAnalysis/update')
          : Uri.parse('$kApiBaseUrl/cp/houseAnalysis');
      final resp = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer ${user.token}',
        },
        body: json.encode(body),
      );

      if (!mounted) return;

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data is Map && (data['code'] == 200 || data['code'] == '200')) {
          // 成功后跳转到分析列表页面（新页面会在 initState 中自动重新加载数据）
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HouseAnalysisListPage()),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('保存失败：${data['msg'] ?? '未知错误'}'),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败，状态码：${resp.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存异常：$e')),
      );
    }
  }
}
