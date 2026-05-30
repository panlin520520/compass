import 'dart:convert';
import 'dart:math';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'compass_detail_page.dart';
import 'house_analysis_page.dart';
import 'luban_ruler_page.dart';
import 'level_page.dart';
import 'decibel_page.dart';
import 'liji_ruler_page.dart';
import 'login_page.dart';
import 'auth_service.dart';
import 'feedback_page.dart';
import 'about_page.dart';
import 'style_preference_api.dart';
import 'webview_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.init();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '罗盘',
      theme: ThemeData(
        primarySwatch: Colors.red,
        // 勿写死仅 macOS/iOS 自带的 PingFang SC；Windows/Android 无该字体会导致中文乱码或方块
      ),
      home: const PrivacyConsentGate(child: MainPage()),
    );
  }
}

// 主页面，包含底部导航栏
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;
  String _currentCompassPath = 'assets/gold/0-SimplePlate-BaguaTwentyFour.png';
  bool _showCompassList = false; // 控制是否显示罗盘列表
  String? _currentBackgroundPath; // 当前背景路径
  /// 首页智能读盘或实景罗盘开启时隐藏底部导航栏
  bool _hideBottomNavOnHome = false;

  @override
  void initState() {
    super.initState();
    _loadSavedStyles();
  }

  /// 加载首页罗盘、背景等样式（本地缓存优先，登录后合并服务端）
  Future<void> _loadSavedStyles() async {
    final prefs = await StylePreferenceApi.loadPreferences('compass');
    setState(() {
      final plate = prefs['compassPlate'];
      if (plate != null && plate.isNotEmpty) {
        _currentCompassPath = plate;
      }
      final bg = prefs['background'];
      if (bg != null) {
        _currentBackgroundPath = bg.isEmpty ? null : bg;
      }
    });
  }

  void _onCompassSelected(String compassPath) {
    setState(() {
      _currentCompassPath = compassPath;
      _showCompassList = false; // 切换回详情页
    });
    // 持久化罗盘样式
    StylePreferenceApi.savePreference(
      page: 'compass',
      prefKey: 'compassPlate',
      prefValue: compassPath,
    );
  }

  void _showCompassListPage() {
    setState(() {
      _showCompassList = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 首页内容：根据_showCompassList决定显示详情页还是列表页
    Widget homePage;
    if (_showCompassList) {
      homePage = CompassHomePage(
        onCompassSelected: _onCompassSelected,
        onBack: () {
          setState(() {
            _showCompassList = false;
          });
        },
        onCompassDialSelected: (String dialImage) {
          // 首页中选择“指南针样式”暂不需要额外导航，
          // 这里只是占位，避免误调用 Navigator.pop 导致黑屏退出
        },
        onBackgroundSelected: (String backgroundPath) {
          setState(() {
            _currentBackgroundPath =
                backgroundPath.isEmpty ? null : backgroundPath;
            _showCompassList = false;
          });
          // 持久化背景样式（空字符串表示默认白色）
          StylePreferenceApi.savePreference(
            page: 'compass',
            prefKey: 'background',
            prefValue: backgroundPath,
          );
        },
        currentBackgroundPath: _currentBackgroundPath,
      );
    } else {
      homePage = CompassDetailPage(
        compassImagePath: _currentCompassPath,
        onMenuPressed: _showCompassListPage,
        backgroundImagePath: _currentBackgroundPath,
        onSmartTipModeChanged: (active) {
          setState(() => _hideBottomNavOnHome = active);
        },
      );
    }

    final List<Widget> pages = [
      homePage,
      const HexagramListPage(),
      const HexagramCalculatorPage(),
      const MatterRecordsPage(),
      const ToolsPage(),
      // const BooksPage(), // 书籍 tab 暂时注释掉
      const ProfilePage(),
    ];

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: _currentIndex == 0 && _hideBottomNavOnHome
          ? null
          : BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedFontSize: 11,
        unselectedFontSize: 10,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
            // 如果切换到首页，默认显示详情页
            if (index == 0) {
              _showCompassList = false;
            }
          });
        },
        type: BottomNavigationBarType.fixed,
        selectedItemColor: Colors.red,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: '首页',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.grid_view_rounded),
            label: '卦象列表',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calculate_outlined),
            label: '卦象计算',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.event_note_outlined),
            label: '事项记录',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.build),
            label: '工具',
          ),
          // BottomNavigationBarItem(
          //   icon: Icon(Icons.menu_book),
          //   label: '书籍',
          // ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: '我的',
          ),
        ],
      ),
    );
  }
}

// 罗盘列表页
class CompassHomePage extends StatefulWidget {
  final Function(String)? onCompassSelected;
  final VoidCallback? onBack;
  final Function(String)? onCompassDialSelected; // 指南针表盘选择回调
  final Function(String)? onBackgroundSelected; // 背景选择回调
  final String? currentBackgroundPath; // 当前选中的背景路径
  /// 从指南针页进入时仅展示「指南针」表盘，隐藏「罗盘」「背景」。
  final bool compassDialOnly;

  const CompassHomePage({
    super.key,
    this.onCompassSelected,
    this.onBack,
    this.onCompassDialSelected,
    this.onBackgroundSelected,
    this.currentBackgroundPath,
    this.compassDialOnly = false,
  });

  @override
  State<CompassHomePage> createState() => _CompassHomePageState();
}

class _CompassHomePageState extends State<CompassHomePage> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  String _selectedCompassType = '金色罗盘';

  final List<String> _compassTypes = ['金色罗盘', '黑色罗盘', '白色罗盘'];

  bool get _dialOnly => widget.compassDialOnly;

  @override
  void initState() {
    super.initState();
    if (!_dialOnly) {
      _tabController = TabController(length: 3, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }
  
  // 中英文名称映射
  final Map<String, String> _compassNameMap = {
    'SimplePlate-BaguaTwentyFour': '简易盘-八卦二十四山',
    'SimplePlate-TwentyFourDirection': '简易盘-二十四方位',
    'BeginnerPlate': '入门盘',
    'Beginner-XuankongPlate': '入门-玄空盘',
    'SanhePlate-KaixiSuDu': '三合盘-开禧宿度',
    'SanyuanPlate-ShixianSuDu': '三元盘-时宪宿度',
    'XuankongFeixing-EightNineYun': '玄空飞星-八运九运',
    'TwentyEightLayerComprehensive': '二十八层综合盘',
    'JinsuoYuguanPlate': '金锁玉关盘',
    'XiangshangTwelveChangSheng': '向上十二长生',
    'LongmenBaju': '龙门八局',
    'BazhaiFengshui': '八宅风水',
    'JiuxingFangua': '九星翻卦',
  };
  
  // 背景中英文名称映射（英文名称 -> 中文名称）
  final Map<String, String> _backgroundNameMap = {
    'DefaultWhite': '默认白色',
    'TraditionalLandscape1': '国风山水1',
    'TraditionalLandscape2': '国风山水2',
    'Landscape': '山水',
    'WoodGrain': '木纹',
  };
  
  // 背景文件映射（英文名称 -> 实际文件路径）
  // 优先使用英文文件名，如果不存在则使用中文文件名
  final Map<String, String> _backgroundFileMap = {
    'DefaultWhite': 'assets/background/DefaultWhite.png',
    'TraditionalLandscape1': 'assets/background/TraditionalLandscape1.png', // 如果重命名失败，改为 'assets/background/国风山水1.png'
    'TraditionalLandscape2': 'assets/background/TraditionalLandscape2.png', // 如果重命名失败，改为 'assets/background/国风山水2.png'
    'Landscape': 'assets/background/Landscape.png', // 如果重命名失败，改为 'assets/background/山水.png'
    'WoodGrain': 'assets/background/WoodGrain.png', // 如果重命名失败，改为 'assets/background/木纹.png'
  };
  
  // 罗盘文件列表（按编号顺序）
  final List<String> _compassFiles = [
    '0-SimplePlate-BaguaTwentyFour.png',
    '1-SimplePlate-TwentyFourDirection.png',
    '2-BeginnerPlate.png',
    '3-Beginner-XuankongPlate.png',
    '4-SanhePlate-KaixiSuDu.png',
    '5-SanyuanPlate-ShixianSuDu.png',
    '6-XuankongFeixing-EightNineYun.png',
    '7-TwentyEightLayerComprehensive.png',
    '8-JinsuoYuguanPlate.png',
    '9-XiangshangTwelveChangSheng.png',
    '10-LongmenBaju.png',
    '11-BazhaiFengshui.png',
    '12-JiuxingFangua.png',
  ];
  
  String get _assetPath {
    switch (_selectedCompassType) {
      case '金色罗盘':
        return 'assets/gold';
      case '黑色罗盘':
        return 'assets/black';
      case '白色罗盘':
        return 'assets/white';
      default:
        return 'assets/gold';
    }
  }
  
  // 从文件名提取英文名称
  String _getEnglishName(String fileName) {
    // 移除编号前缀和.png后缀，例如: 0-SimplePlate-BaguaTwentyFour.png -> SimplePlate-BaguaTwentyFour
    String name = fileName.replaceAll(RegExp(r'^\d+-'), '').replaceAll('.png', '');
    return name;
  }
  
  // 获取中文名称
  String _getChineseName(String fileName) {
    String englishName = _getEnglishName(fileName);
    return _compassNameMap[englishName] ?? englishName;
  }
  
  List<Map<String, String>> get _compassImages {
    return _compassFiles.map((fileName) {
      String englishName = _getEnglishName(fileName);
      return {
        'path': '$_assetPath/$fileName',
        'name': _getChineseName(fileName),
        'englishName': englishName,
      };
    }).toList();
  }

  PreferredSizeWidget? _styleTabBar() {
    if (_dialOnly || _tabController == null) return null;
    return TabBar(
      controller: _tabController,
      labelColor: Colors.red,
      unselectedLabelColor: Colors.grey,
      indicatorColor: Colors.red,
      tabs: const [
        Tab(text: '指南针'),
        Tab(text: '罗盘'),
        Tab(text: '背景'),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final fromHomeStyle = widget.onCompassSelected != null && !_dialOnly;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: fromHomeStyle
          ? AppBar(
              title: const Text('样式'),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black),
                onPressed: () {
                  if (widget.onBack != null) {
                    widget.onBack!();
                  }
                },
              ),
              bottom: _styleTabBar(),
            )
          : AppBar(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0,
              title: Text(_dialOnly ? '样式' : '罗盘'),
              leading: _dialOnly
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: () {
                        if (widget.onBack != null) {
                          widget.onBack!();
                        } else {
                          Navigator.of(context).maybePop();
                        }
                      },
                    )
                  : null,
              automaticallyImplyLeading: !_dialOnly,
              bottom: _styleTabBar(),
            ),
      body: _dialOnly
          ? _buildCompassTab()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildCompassTab(),
                _buildCompassListTab(),
                _buildBackgroundTab(),
              ],
            ),
    );
  }
  
  // 指南针tab内容
  Widget _buildCompassTab() {
    final compassDials = [
      {
        'name': '黑色表盘',
        'image': 'assets/compass/black.png',
      },
      {
        'name': '白色表盘',
        'image': 'assets/compass/white.png',
      },
    ];

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemCount: compassDials.length,
                itemBuilder: (context, index) {
                  final dial = compassDials[index];
                  return GestureDetector(
                    onTap: () {
                      // 如果是从指南针页面跳转过来的，返回并更新表盘
                      if (widget.onCompassDialSelected != null) {
                        widget.onCompassDialSelected!(dial['image']!);
                      } else if (widget.onCompassSelected != null) {
                        widget.onCompassSelected!(dial['image']!);
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.2),
                            spreadRadius: 1,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AppAssetImage(
                            assetPath: dial['image']!,
                            width: 80,
                            height: 80,
                            fit: BoxFit.contain,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            dial['name']!,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // 罗盘tab内容
  Widget _buildCompassListTab() {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            // 罗盘列表部分
            _buildCompassListSection(),
            const SizedBox(height: 20),
            // 罗盘图片网格
            _buildCompassGrid(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
  
  // 背景tab内容
  Widget _buildBackgroundTab() {
    // 背景列表数据（首项为默认白色，image 为空表示无背景图）
    final List<Map<String, String>> backgrounds = [
      {
        'key': 'DefaultWhite',
        'name': _backgroundNameMap['DefaultWhite']!,
        'image': '',
        'preview': _backgroundFileMap['DefaultWhite']!,
      },
      {
        'key': 'TraditionalLandscape1',
        'name': _backgroundNameMap['TraditionalLandscape1']!,
        'image': _backgroundFileMap['TraditionalLandscape1']!,
      },
      {
        'key': 'TraditionalLandscape2',
        'name': _backgroundNameMap['TraditionalLandscape2']!,
        'image': _backgroundFileMap['TraditionalLandscape2']!,
      },
      {
        'key': 'Landscape',
        'name': _backgroundNameMap['Landscape']!,
        'image': _backgroundFileMap['Landscape']!,
      },
      {
        'key': 'WoodGrain',
        'name': _backgroundNameMap['WoodGrain']!,
        'image': _backgroundFileMap['WoodGrain']!,
      },
    ];
    
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              // 背景选择网格
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.7,
                ),
                itemCount: backgrounds.length,
                itemBuilder: (context, index) {
                  final background = backgrounds[index];
                  final imagePath = background['image']!;
                  final isDefaultWhite = imagePath.isEmpty;
                  final displayPath = isDefaultWhite
                      ? background['preview']!
                      : imagePath;
                  final currentPath = widget.currentBackgroundPath;
                  final isSelected = isDefaultWhite
                      ? currentPath == null || currentPath.isEmpty
                      : currentPath == imagePath;

                  return GestureDetector(
                    onTap: () {
                      if (widget.onBackgroundSelected != null) {
                        widget.onBackgroundSelected!(imagePath);
                      }
                    },
                    child: Column(
                      children: [
                        // 预览图片
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? Colors.blue : Colors.grey[300]!,
                                width: isSelected ? 2 : 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.grey.withOpacity(0.2),
                                  spreadRadius: 1,
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: AppAssetImage(
                                assetPath: displayPath,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey[200],
                                    child: const Icon(
                                        Icons.image_not_supported),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // 中文名称
                        Text(
                          background['name']!,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        // 按钮
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.blue[100] : Colors.grey[200],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isSelected ? '当前' : '切换',
                            style: TextStyle(
                              fontSize: 12,
                              color: isSelected ? Colors.blue[800] : Colors.grey[700],
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Expanded(
            child: Center(
              child: Text(
                '罗盘',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey,
            ),
            child: const Icon(
              Icons.add,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildToolGrid() {
    final tools = [
      {
        'name': '水平尺',
        'icon': Icons.straighten,
        'color': Colors.amber,
      },
      {
        'name': '鲁班尺',
        'icon': Icons.square_foot,
        'color': Colors.amber,
      },
      {
        'name': '立极尺',
        'icon': Icons.compass_calibration,
        'color': Colors.blue,
      },
      {
        'name': '房屋分析',
        'icon': Icons.home,
        'color': Colors.orange,
      },
      {
        'name': '地图罗盘',
        'icon': Icons.map,
        'color': Colors.blue,
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: tools.map((tool) {
          return Expanded(
            child: Column(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: tool['color'] as Color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    tool['icon'] as IconData,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  tool['name'] as String,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCompassListSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '罗盘列表',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          DropdownButton<String>(
            value: _selectedCompassType,
            underline: Container(),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.grey),
            items: _compassTypes.map((String type) {
              return DropdownMenuItem<String>(
                value: type,
                child: Text(
                  type,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black,
                  ),
                ),
              );
            }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedCompassType = newValue;
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCompassGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.85,
        ),
        itemCount: _compassImages.length,
        itemBuilder: (context, index) {
          final compass = _compassImages[index];
            return GestureDetector(
            onTap: () {
              if (widget.onCompassSelected != null) {
                widget.onCompassSelected!(compass['path']!);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => CompassDetailPage(
                      compassImagePath: compass['path']!,
                    ),
                  ),
                );
              }
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    spreadRadius: 1,
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                      child: AppAssetImage(
                        assetPath: compass['path']!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(Icons.error, color: Colors.grey),
                          );
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      compass['name']!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// 工具页
class ToolsPage extends StatelessWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('工具'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFF1E3A5F), // 深蓝色背景
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              // 工具网格
              _buildToolGrid(),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildToolGrid() {
    final tools = [
      {
        'name': '鲁班尺',
        'icon': Icons.square_foot,
        'subtitle': '',
      },
      {
        'name': '房屋分析',
        'icon': Icons.home,
        'subtitle': '',
      },
      {
        'name': '水平仪',
        'icon': Icons.straighten,
        'subtitle': '',
      },
      {
        'name': '测分贝',
        'icon': Icons.graphic_eq,
        'subtitle': '',
      },
      {
        'name': '立极尺',
        'icon': Icons.compass_calibration,
        'subtitle': '',
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.5,
        ),
        itemCount: tools.length,
        itemBuilder: (context, index) {
          final tool = tools[index];
          return Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF5E6D3), // 浅米色背景
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  // 工具点击事件
                  if (tool['name'] == '鲁班尺') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LubanRulerPage(),
                      ),
                    );
                  } else if (tool['name'] == '水平仪') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LevelPage(),
                      ),
                    );
                  } else if (tool['name'] == '测分贝') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const DecibelPage(),
                      ),
                    );
                  } else if (tool['name'] == '房屋分析') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const HouseAnalysisPage(),
                      ),
                    );
                  } else if (tool['name'] == '立极尺') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LijiRulerPage(),
                      ),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(12),
                  child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 左边文字
                      Expanded(
                        child: Text(
                          tool['name'] as String,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 右边圆形图标
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.amber[800],
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          tool['icon'] as IconData,
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// 书籍页
class BooksPage extends StatelessWidget {
  const BooksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('书籍'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: const Center(
        child: Text(
          '书籍页面',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}

// 我的页面
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff4f4f4),
      body: SafeArea(
        child: Column(
          children: [
            // 顶部背景图区域
            SizedBox(
              height: 200,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AppAssetImage(
                    assetPath: 'assets/my/边框.png',
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    left: 16,
                    bottom: 32,
                    child: ValueListenableBuilder<AuthUser?>(
                      valueListenable: AuthService.currentUser,
                      builder: (context, user, _) {
                        if (user == null) {
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const LoginPage()),
                              );
                            },
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: AppAssetImage(
                                    assetPath: 'assets/logo.png',
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '登录/注册',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '点击登录/注册',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.85),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }

                        final nickName = user.nickName.isNotEmpty ? user.nickName : '用户';
                        final avatar = user.avatar;
                        final hasNetworkAvatar = avatar.startsWith('http://') || avatar.startsWith('https://');

                        return Row(
                          children: [
                            CircleAvatar(
                              radius: 28,
                              backgroundColor: Colors.white.withOpacity(0.2),
                              backgroundImage: hasNetworkAvatar ? NetworkImage(avatar) : null,
                              child: (!hasNetworkAvatar || avatar.isEmpty)
                                  ? const Icon(Icons.person, color: Colors.white, size: 32)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  nickName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '已登录',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.85),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 中间白色功能卡片
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  // 第一排：三等分宽度
                  Row(
                    children: [
                      Expanded(
                        child: _ProfileItem(
                          icon: Icons.info_outline,
                          label: '关于我们',
                          type: _ProfileItemType.about,
                        ),
                      ),
                      Expanded(
                        child: _ProfileItem(
                          icon: Icons.feedback_outlined,
                          label: '问题反馈',
                          type: _ProfileItemType.feedback,
                        ),
                      ),
                      Expanded(
                        child: _ProfileItem(
                          icon: Icons.headset_mic_outlined,
                          label: '我的客服',
                          type: _ProfileItemType.support,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  // 第二排：与上一排列宽对齐，把“设置”放在第一列
                  Row(
                    children: [
                      Expanded(
                        child: _ProfileItem(
                          icon: Icons.settings_outlined,
                          label: '设置',
                          type: _ProfileItemType.settings,
                        ),
                      ),
                      Expanded(child: SizedBox()),
                      Expanded(child: SizedBox()),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ProfileItemType { about, settings, feedback, support }

class _ProfileItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final _ProfileItemType type;

  const _ProfileItem({
    required this.icon,
    required this.label,
    required this.type,
  });

  void _onTap(BuildContext context) {
    Widget page;
    switch (type) {
      case _ProfileItemType.about:
        page = const AboutPage();
        break;
      case _ProfileItemType.settings:
        page = const SettingsPage();
        break;
      case _ProfileItemType.feedback:
        page = const FeedbackPage();
        break;
      case _ProfileItemType.support:
        page = const CustomerServicePage();
        break;
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _onTap(context),
      borderRadius: BorderRadius.circular(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: const Color(0xfff4f0ea),
            child: Icon(
              icon,
              color: const Color(0xff27201a),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// 简单占位页面，后续可以替换为真实页面
class _SimpleInfoPage extends StatelessWidget {
  final String title;
  final String content;

  const _SimpleInfoPage({
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Center(
        child: Text(
          content,
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

/// 设置页
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const Color _logoutRed = Color(0xFFE53935);
  static const Color _mutedText = Color(0xFF888888);

  Future<void> _logout() async {
    await AuthService.logout();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmLogout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出', style: TextStyle(color: _logoutRed)),
          ),
        ],
      ),
    );
    if (ok == true) await _logout();
  }

  Future<void> _confirmDeleteAccount(AuthUser user) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('账号注销'),
        content: const Text(
          '注销后您的测量记录、事项记录、房屋分析等数据将被永久删除且无法恢复，是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('继续注销', style: TextStyle(color: _logoutRed)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AccountDeleteVerifyDialog(user: user),
    );
    if (deleted == true && mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('账号已注销')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF5F5F5),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ValueListenableBuilder<AuthUser?>(
          valueListenable: AuthService.currentUser,
          builder: (context, user, _) {
            final loggedIn = user != null;
            final accountLabel = user == null
                ? '当前未登录'
                : '当前账号：${user.nickName.isEmpty ? '用户' : user.nickName}';

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        accountLabel,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF222222),
                        ),
                      ),
                      if (loggedIn && user.displayPhone.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          user.displayPhone,
                          style: const TextStyle(fontSize: 14, color: _mutedText),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    onPressed: loggedIn ? _confirmLogout : null,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _logoutRed,
                      side: BorderSide(
                        color: loggedIn ? _logoutRed.withOpacity(0.45) : Colors.grey.shade300,
                      ),
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '退出登录',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: TextButton(
                    onPressed: loggedIn ? () => _confirmDeleteAccount(user!) : null,
                    style: TextButton.styleFrom(
                      foregroundColor: loggedIn ? _mutedText : Colors.grey.shade400,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '账号注销',
                      style: TextStyle(fontSize: 15),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 账号注销 · 短信验证弹窗（独立 State 管理 Controller 生命周期）
class _AccountDeleteVerifyDialog extends StatefulWidget {
  const _AccountDeleteVerifyDialog({required this.user});

  final AuthUser user;

  @override
  State<_AccountDeleteVerifyDialog> createState() =>
      _AccountDeleteVerifyDialogState();
}

class _AccountDeleteVerifyDialogState extends State<_AccountDeleteVerifyDialog> {
  static const Color _logoutRed = Color(0xFFE53935);
  static const Color _mutedText = Color(0xFF888888);

  late final TextEditingController _phoneCtrl;
  late final TextEditingController _codeCtrl;
  bool _sending = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _phoneCtrl = TextEditingController(text: widget.user.displayPhone);
    _codeCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      _showSnack('请输入正确的手机号');
      return;
    }
    setState(() => _sending = true);
    final err = await AuthService.sendSmsCode(phone);
    if (!mounted) return;
    setState(() => _sending = false);
    _showSnack(err ?? '验证码已发送');
  }

  Future<void> _submit() async {
    final phone = _phoneCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (!RegExp(r'^1\d{10}$').hasMatch(phone)) {
      _showSnack('请输入正确的手机号');
      return;
    }
    if (code.isEmpty) {
      _showSnack('请输入验证码');
      return;
    }
    setState(() => _submitting = true);
    final err = await AuthService.deleteAccount(
      userId: widget.user.userId,
      phoneNumber: phone,
      smsCode: code,
    );
    if (!mounted) return;
    if (err == null) {
      if (mounted) Navigator.pop(context, true);
      return;
    }
    if (!mounted) return;
    setState(() => _submitting = false);
    _showSnack(err);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('验证身份'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '为保障账号安全，请验证注册手机号后完成注销。',
              style: TextStyle(fontSize: 14, color: _mutedText, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: '手机号',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _codeCtrl,
                    keyboardType: TextInputType.number,
                    enabled: !_submitting,
                    decoration: const InputDecoration(
                      labelText: '验证码',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: (_sending || _submitting) ? null : _sendCode,
                  child: Text(_sending ? '发送中…' : '获取验证码'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: _logoutRed),
          child: Text(_submitting ? '提交中…' : '确认注销'),
        ),
      ],
    );
  }
}

// --- 卦象列表 / 卦象计算 / 事项记录（内联于本文件，避免独立 dart 未被分析器收录） ---

/// 与「大师罗盘」类应用一致的浅金 + 白卡片风格。
const Color _kHexPageBg = Color(0xFFF7F4EF);
const Color _kHexCardBg = Colors.white;
const Color _kHexAccent = Color(0xFFC69C52);
const Color _kHexTitleColor = Color(0xFF2C2416);

class _HexFeatureScaffold extends StatelessWidget {
  const _HexFeatureScaffold({
    required this.title,
    required this.body,
    this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kHexPageBg,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(
            color: _kHexTitleColor,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        backgroundColor: _kHexCardBg,
        foregroundColor: _kHexTitleColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.black.withOpacity(0.06)),
        ),
      ),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}

class _GuaXiangEntry {
  const _GuaXiangEntry({
    required this.name,
    required this.symbol,
    required this.meaning,
    required this.analysis,
  });

  final String name;
  final String symbol;
  final String meaning;
  final String analysis;

  factory _GuaXiangEntry.fromJson(Map<String, dynamic> json) {
    return _GuaXiangEntry(
      name: (json['name'] ?? '').toString(),
      symbol: (json['symbol'] ?? '').toString(),
      meaning: (json['meaning'] ?? '').toString(),
      analysis: (json['analysis'] ?? '').toString(),
    );
  }
}

/// 卦象列表（数据来自 assets/guaXiangLieBiao.json）
class HexagramListPage extends StatefulWidget {
  const HexagramListPage({super.key});

  @override
  State<HexagramListPage> createState() => _HexagramListPageState();
}

class _HexagramListPageState extends State<HexagramListPage> {
  List<_GuaXiangEntry>? _items;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    try {
      final raw =
          await loadAppAssetString('assets/guaXiangLieBiao.json') ?? '';
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const FormatException('guaXiangLieBiao.json 应为数组');
      }
      if (!mounted) return;
      setState(() {
        _items = decoded
            .whereType<Map>()
            .map((e) => _GuaXiangEntry.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.name.isNotEmpty)
            .toList();
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = null;
        _error = e.toString();
      });
    }
  }

  void _openDetail(_GuaXiangEntry item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HexagramDetailPage(item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kHexPageBg,
      appBar: AppBar(
        backgroundColor: _kHexPageBg,
        foregroundColor: _kHexTitleColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const SizedBox.shrink(),
        centerTitle: false,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Text(
              '卦象的列表',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: _kHexTitleColor,
                height: 1.2,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _buildListCard(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListCard() {
    if (_error != null) {
      return _cardShell(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '加载失败：$_error',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[700]),
            ),
          ),
        ),
      );
    }
    if (_items == null) {
      return _cardShell(
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    final items = _items!;
    if (items.isEmpty) {
      return _cardShell(
        child: const Center(child: Text('暂无卦象数据')),
      );
    }
    return _cardShell(
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: items.length,
        separatorBuilder: (_, __) => Divider(
          height: 1,
          thickness: 1,
          color: Colors.grey.withOpacity(0.15),
          indent: 72,
        ),
        itemBuilder: (context, index) {
          final item = items[index];
          return InkWell(
            onTap: () => _openDetail(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(
                      item.symbol,
                      style: const TextStyle(
                        fontSize: 28,
                        height: 1.15,
                        color: _kHexTitleColor,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: _kHexTitleColor,
                            height: 1.25,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.meaning,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 8),
                    child: Icon(
                      Icons.chevron_right,
                      color: Colors.grey[400],
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cardShell({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: _kHexCardBg,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// 卦象详情页
class HexagramDetailPage extends StatelessWidget {
  const HexagramDetailPage({super.key, required this.item});

  final _GuaXiangEntry item;

  static const Color _linkBlue = Color(0xFF2B7FFF);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leadingWidth: 132,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.only(left: 4, right: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            alignment: Alignment.centerLeft,
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chevron_left, color: _linkBlue, size: 28),
              Text(
                '卦象的列表',
                style: TextStyle(
                  color: _linkBlue,
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
        title: Text(
          item.name,
          style: const TextStyle(
            color: _kHexTitleColor,
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              item.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                color: _kHexTitleColor,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              item.symbol,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 88,
                height: 1.05,
                color: _kHexTitleColor,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 36),
            Text(
              item.meaning,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[800],
                height: 1.5,
              ),
            ),
            if (item.analysis.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text(
                item.analysis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[700],
                  height: 1.55,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 卦象计算：按参考界面——标题、月历选日、生成卦象、结果卡片（演示用）。
class HexagramCalculatorPage extends StatefulWidget {
  const HexagramCalculatorPage({super.key});

  @override
  State<HexagramCalculatorPage> createState() => _HexagramCalculatorPageState();
}

class _HexagramCalculatorPageState extends State<HexagramCalculatorPage> {
  static const Color _blue = Color(0xFF2B7FFF);
  static const Color _lightBlue = Color(0xFFDCEBFF);
  static const List<String> _weekLabels = [
    'SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT',
  ];
  static const List<String> _enMonths = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  /// 当前展示的月份（仅年月有效）
  DateTime _focusedMonth = DateTime.now();
  DateTime? _selectedDay = DateTime.now();
  List<_GuaXiangEntry>? _entries;
  String? _loadError;
  _GuaXiangEntry? _generatedResult;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    try {
      final raw =
          await loadAppAssetString('assets/guaXiangLieBiao.json') ?? '';
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        throw const FormatException('guaXiangLieBiao.json 应为数组');
      }
      if (!mounted) return;
      setState(() {
        _entries = decoded
            .whereType<Map>()
            .map((e) => _GuaXiangEntry.fromJson(Map<String, dynamic>.from(e)))
            .where((e) => e.name.isNotEmpty)
            .toList();
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _entries = null;
        _loadError = e.toString();
      });
    }
  }

  List<String> _trigramChars(String symbol) {
    return symbol.runes.map((r) => String.fromCharCode(r)).toList();
  }

  Widget _buildGeneratedResultCard(_GuaXiangEntry entry) {
    final trigrams = _trigramChars(entry.symbol);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text(
          '生成的卦象',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111111),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (trigrams.isNotEmpty)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: trigrams
                    .map(
                      (t) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          t,
                          style: const TextStyle(
                            fontSize: 34,
                            height: 1.1,
                            color: Color(0xFF111111),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            if (trigrams.isNotEmpty) const SizedBox(width: 20),
            Text(
              entry.name,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111111),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          entry.meaning,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            height: 1.45,
            color: Colors.grey[800],
          ),
        ),
      ],
    );
  }

  int _firstBlankCount(DateTime firstOfMonth) {
    return firstOfMonth.weekday % 7;
  }

  void _prevMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    });
  }

  Future<void> _openMonthYearPicker() async {
    const yearStart = 1920;
    const yearEnd = 2100;
    final initial = _selectedDay ?? _focusedMonth;
    var pickedMonth = initial.month;
    var pickedYear = initial.year;

    final monthController =
        FixedExtentScrollController(initialItem: pickedMonth - 1);
    final yearController =
        FixedExtentScrollController(initialItem: pickedYear - yearStart);

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(sheetContext, false),
                      child: Text(
                        '取消',
                        style: TextStyle(color: Colors.grey[700], fontSize: 16),
                      ),
                    ),
                    const Expanded(
                      child: Text(
                        '选择年月',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111111),
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(sheetContext, true),
                      child: const Text(
                        '确定',
                        style: TextStyle(
                          color: _blue,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 220,
                child: CupertinoTheme(
                  data: const CupertinoThemeData(brightness: Brightness.light),
                  child: Row(
                    children: [
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: monthController,
                          itemExtent: 40,
                          magnification: 1.08,
                          squeeze: 1.1,
                          useMagnifier: true,
                          onSelectedItemChanged: (index) {
                            pickedMonth = index + 1;
                          },
                          children: _enMonths
                              .map(
                                (m) => Center(
                                  child: Text(
                                    m,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      color: Color(0xFF222222),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      Expanded(
                        child: CupertinoPicker(
                          scrollController: yearController,
                          itemExtent: 40,
                          magnification: 1.08,
                          squeeze: 1.1,
                          useMagnifier: true,
                          onSelectedItemChanged: (index) {
                            pickedYear = yearStart + index;
                          },
                          children: List.generate(
                            yearEnd - yearStart + 1,
                            (i) => Center(
                              child: Text(
                                '${yearStart + i}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  color: Color(0xFF222222),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (confirmed == true) {
      pickedMonth = monthController.selectedItem + 1;
      pickedYear = yearStart + yearController.selectedItem;
    }
    monthController.dispose();
    yearController.dispose();

    if (confirmed != true || !mounted) return;

    setState(() {
      _focusedMonth = DateTime(pickedYear, pickedMonth);
      final lastDay = DateTime(pickedYear, pickedMonth + 1, 0).day;
      final keepDay = _selectedDay?.day ?? 1;
      _selectedDay = DateTime(
        pickedYear,
        pickedMonth,
        keepDay.clamp(1, lastDay),
      );
    });
  }

  void _generate() {
    final items = _entries;
    if (items == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('卦象数据加载中，请稍候…')),
      );
      return;
    }
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_loadError ?? '暂无卦象数据'),
        ),
      );
      return;
    }
    setState(() {
      _generatedResult = items[_random.nextInt(items.length)];
    });
  }

  @override
  Widget build(BuildContext context) {
    final first = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDay = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final blanks = _firstBlankCount(first);
    final totalCells = ((blanks + lastDay + 6) ~/ 7) * 7;
    final monthTitle =
        '${_enMonths[_focusedMonth.month - 1]} ${_focusedMonth.year}';

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '卦象的计算器',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111111),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '选择日期生成卦象',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[700],
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _openMonthYearPicker,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              monthTitle,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111111),
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(
                              Icons.chevron_right,
                              size: 22,
                              color: _blue.withOpacity(0.9),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: _prevMonth,
                    icon: const Icon(Icons.chevron_left, color: _blue, size: 28),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: _nextMonth,
                    icon: const Icon(Icons.chevron_right, color: _blue, size: 28),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: _weekLabels
                    .map(
                      (w) => Expanded(
                        child: Center(
                          child: Text(
                            w,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey[500],
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 4,
                  childAspectRatio: 1.05,
                ),
                itemCount: totalCells,
                itemBuilder: (context, i) {
                  if (i < blanks || i >= blanks + lastDay) {
                    return const SizedBox.shrink();
                  }
                  final day = i - blanks + 1;
                  final cellDate = DateTime(
                    _focusedMonth.year,
                    _focusedMonth.month,
                    day,
                  );
                  final sel = _selectedDay;
                  final isSel = sel != null &&
                      sel.year == cellDate.year &&
                      sel.month == cellDate.month &&
                      sel.day == cellDate.day;
                  return InkWell(
                    onTap: () => setState(() => _selectedDay = cellDate),
                    customBorder: const CircleBorder(),
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isSel ? _lightBlue : Colors.transparent,
                        ),
                        child: Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                isSel ? FontWeight.w600 : FontWeight.w500,
                            color: const Color(0xFF222222),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: _generate,
                  child: const Text(
                    '生成卦象',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: _generatedResult != null
                    ? _buildGeneratedResultCard(_generatedResult!)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Text(
                            '生成的卦象',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111111),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '选择日期后点击「生成卦象」',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 事项记录（与后端 cp/matterRecord 接口对应）
class MatterRecordItem {
  MatterRecordItem({
    required this.id,
    required this.title,
    required this.note,
    this.createTime,
  });

  final int id;
  final String title;
  final String note;
  final DateTime? createTime;

  static MatterRecordItem fromJson(Map<String, dynamic> m) {
    DateTime? parseTime(dynamic v) {
      if (v == null) return null;
      final s = v.toString();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s.replaceFirst(' ', 'T'));
    }

    return MatterRecordItem(
      id: int.tryParse(m['id']?.toString() ?? '') ?? 0,
      title: (m['title'] ?? '').toString(),
      note: (m['note'] ?? m['remark'] ?? m['content'] ?? '').toString(),
      createTime: parseTime(m['createTime'] ?? m['create_time']),
    );
  }
}

class MatterRecordApi {
  MatterRecordApi._();

  static Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $token',
      };

  static void _ensureOk(Map<dynamic, dynamic> data) {
    final code = data['code'];
    if (code != 200 && code != '200') {
      throw Exception(data['msg']?.toString() ?? '请求失败');
    }
  }

  static List<MatterRecordItem> _parseList(dynamic dataField) {
    if (dataField is! List) return [];
    return dataField
        .map((e) => MatterRecordItem.fromJson(
              e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map),
            ))
        .where((e) => e.id > 0 && e.title.isNotEmpty)
        .toList();
  }

  static MatterRecordItem _parseOne(dynamic dataField) {
    if (dataField is Map) {
      return MatterRecordItem.fromJson(
        dataField is Map<String, dynamic>
            ? dataField
            : Map<String, dynamic>.from(dataField),
      );
    }
    throw Exception('返回数据格式异常');
  }

  static Future<List<MatterRecordItem>> fetchList({
    required int userId,
    required String token,
  }) async {
    final resp = await http.get(
      Uri.parse('$kApiBaseUrl/cp/matterRecord/list?userId=$userId'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('加载失败，状态码：${resp.statusCode}');
    }
    final decoded = json.decode(resp.body);
    if (decoded is! Map) throw Exception('加载失败：响应格式异常');
    _ensureOk(decoded);
    final items = _parseList(decoded['data']);
    items.sort((a, b) {
      final ta = a.createTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final tb = b.createTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    return items;
  }

  static Future<MatterRecordItem> create({
    required int userId,
    required String token,
    required String title,
    required String note,
  }) async {
    final resp = await http.post(
      Uri.parse('$kApiBaseUrl/cp/matterRecord'),
      headers: _headers(token),
      body: json.encode({
        'userId': userId,
        'title': title,
        'note': note,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('保存失败，状态码：${resp.statusCode}');
    }
    final decoded = json.decode(resp.body);
    if (decoded is! Map) throw Exception('保存失败：响应格式异常');
    _ensureOk(decoded);
    return _parseOne(decoded['data']);
  }

  static Future<void> delete({
    required int userId,
    required String token,
    required int id,
  }) async {
    final resp = await http.delete(
      Uri.parse('$kApiBaseUrl/cp/matterRecord/$id?userId=$userId'),
      headers: _headers(token),
    );
    if (resp.statusCode != 200) {
      throw Exception('删除失败，状态码：${resp.statusCode}');
    }
    final decoded = json.decode(resp.body);
    if (decoded is! Map) throw Exception('删除失败：响应格式异常');
    _ensureOk(decoded);
  }
}

/// 事项记录
class MatterRecordsPage extends StatefulWidget {
  const MatterRecordsPage({super.key});

  @override
  State<MatterRecordsPage> createState() => _MatterRecordsPageState();
}

class _MatterRecordsPageState extends State<MatterRecordsPage> {
  final List<MatterRecordItem> _items = [];
  bool _loading = true;
  String? _error;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = AuthService.currentUser.value;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '请先登录后查看事项记录';
        _items.clear();
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await MatterRecordApi.fetchList(
        userId: user.userId,
        token: user.token,
      );
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(list);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
        _items.clear();
      });
    }
  }

  Future<void> _addRecord() async {
    final draft = await showDialog<({String title, String note})?>(
      context: context,
      builder: (ctx) => const _NewMatterRecordDialog(),
    );
    if (draft == null || !mounted) return;

    final user = AuthService.currentUser.value;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再保存')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final created = await MatterRecordApi.create(
        userId: user.userId,
        token: user.token,
        title: draft.title,
        note: draft.note,
      );
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _items.removeWhere((MatterRecordItem e) => e.id == created.id);
        _items.insert(0, created);
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('保存成功')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败：$e')),
      );
    }
  }

  Future<void> _delete(MatterRecordItem r) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除事项'),
        content: Text('确定删除「${r.title}」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final user = AuthService.currentUser.value;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录后再删除')),
      );
      return;
    }

    try {
      await MatterRecordApi.delete(
        userId: user.userId,
        token: user.token,
        id: r.id,
      );
      if (!mounted) return;
      setState(() => _items.removeWhere((MatterRecordItem e) => e.id == r.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已删除')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _HexFeatureScaffold(
      title: '事项记录',
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator(color: _kHexAccent))
          else if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey[700],
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            )
          else if (_items.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  '暂无记录\n点击右下角按钮添加事项',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                ),
              ),
            )
          else
            ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 88),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final r = _items[index];
                    final t = r.createTime ?? DateTime.now();
                    final dateStr =
                        '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
                        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
                    return Material(
                      color: _kHexCardBg,
                      borderRadius: BorderRadius.circular(12),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        title: Text(
                          r.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _kHexTitleColor,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dateStr,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (r.note.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  r.note,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[800],
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline,
                              color: Colors.grey[600]),
                          onPressed: () => _delete(r),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                              color: Colors.black.withOpacity(0.04)),
                        ),
                      ),
                    );
                  },
                ),
          if (_submitting)
            Container(
              color: Colors.black26,
              alignment: Alignment.center,
              child: const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(color: _kHexAccent),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _submitting
          ? null
          : FloatingActionButton.extended(
              onPressed: _addRecord,
              backgroundColor: _kHexAccent,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('新建'),
            ),
    );
  }
}

/// 新建事项弹窗（控制器在弹窗 State 内管理，避免 dispose 后仍读取）
class _NewMatterRecordDialog extends StatefulWidget {
  const _NewMatterRecordDialog();

  @override
  State<_NewMatterRecordDialog> createState() => _NewMatterRecordDialogState();
}

class _NewMatterRecordDialogState extends State<_NewMatterRecordDialog> {
  final _titleCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _onSave() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写标题')),
      );
      return;
    }
    Navigator.pop(
      context,
      (title: title, note: _noteCtrl.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新建事项'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: '标题',
                hintText: '简要标题',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '备注（选填）',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _onSave,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 本地记录用户是否已同意服务协议与隐私政策。
class PrivacyConsentStorage {
  PrivacyConsentStorage._();

  static const String _keyAgreed = 'privacy_policy_agreed_v1';

  static Future<bool> hasAgreed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAgreed) ?? false;
  }

  static Future<void> setAgreed(bool agreed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAgreed, agreed);
  }
}

/// App 首次进入时展示的服务协议与隐私政策弹窗。
class PrivacyConsentDialog extends StatelessWidget {
  const PrivacyConsentDialog({super.key});

  void _openWebPage(BuildContext context, String title, String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => WebViewPage(title: title, url: url),
      ),
    );
  }

  Future<void> _onAgree(BuildContext context) async {
    await PrivacyConsentStorage.setAgreed(true);
    if (context.mounted) Navigator.of(context).pop(true);
  }

  void _onDisagree(BuildContext context) {
    Navigator.of(context).pop(false);
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    const linkColor = Color(0xFF3A7BFF);
    const bodyStyle = TextStyle(
      fontSize: 15,
      height: 1.55,
      color: Color(0xFF333333),
    );

    return PopScope(
      canPop: false,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '服务协议和隐私政策',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              RichText(
                textAlign: TextAlign.left,
                text: TextSpan(
                  style: bodyStyle,
                  children: [
                    const TextSpan(
                      text:
                          '请你务必审慎阅读、充分理解“服务协议”和“隐私政策”各条款，包括但不限于：为了更好的向你提供服务，我们需要收集你的设备标识、操作日志等信息用于分析、优化应用性能。你可阅读',
                    ),
                    TextSpan(
                      text: '《服务协议》',
                      style: bodyStyle.copyWith(color: linkColor),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => _openWebPage(
                              context,
                              '服务协议',
                              AboutPage.userAgreementUrl,
                            ),
                    ),
                    const TextSpan(text: '和'),
                    TextSpan(
                      text: '《隐私政策》',
                      style: bodyStyle.copyWith(color: linkColor),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => _openWebPage(
                              context,
                              '隐私政策',
                              AboutPage.privacyPolicyUrl,
                            ),
                    ),
                    const TextSpan(
                      text:
                          '了解详细信息。如果你同意，请点击下面按钮开始接受我们的服务。',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _onAgree(context),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: const Text(
                  '同意',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () => _onDisagree(context),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.black87,
                  minimumSize: const Size(double.infinity, 44),
                ),
                child: const Text(
                  '不同意',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 启动门禁：未同意隐私政策前先展示弹窗，同意后才进入主界面。
///
/// 小米等机型点「不同意」后进程可能仍存活，需在 [AppLifecycleState.resumed]
/// 时再次检查并弹出，否则热恢复不会走 [initState]。
class PrivacyConsentGate extends StatefulWidget {
  const PrivacyConsentGate({super.key, required this.child});

  final Widget child;

  @override
  State<PrivacyConsentGate> createState() => _PrivacyConsentGateState();
}

class _PrivacyConsentGateState extends State<PrivacyConsentGate>
    with WidgetsBindingObserver {
  bool? _agreed;
  bool _dialogShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshConsent();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshConsent();
    }
  }

  Future<void> _refreshConsent() async {
    final agreed = await PrivacyConsentStorage.hasAgreed();
    if (!mounted) return;
    setState(() => _agreed = agreed);
    if (!agreed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _presentConsentDialog();
      });
    }
  }

  Future<void> _presentConsentDialog() async {
    if (!mounted || _dialogShowing || _agreed == true) return;

    if (await PrivacyConsentStorage.hasAgreed()) {
      if (!mounted) return;
      setState(() => _agreed = true);
      return;
    }
    if (!mounted) return;

    _dialogShowing = true;
    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black54,
        builder: (_) => const PrivacyConsentDialog(),
      );

      if (!mounted) return;

      if (result == true || await PrivacyConsentStorage.hasAgreed()) {
        setState(() => _agreed = true);
        return;
      }

      // 未同意：保持门禁。部分机型未真正退出时立即再弹；小米热恢复由 resumed 触发。
      setState(() => _agreed = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _presentConsentDialog();
      });
    } finally {
      _dialogShowing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_agreed != true) {
      return PopScope(
        canPop: false,
        child: const ColoredBox(
          color: Colors.white,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return widget.child;
  }
}
