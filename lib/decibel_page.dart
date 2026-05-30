import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'dart:math' as math;

class DecibelPage extends StatefulWidget {
  const DecibelPage({super.key});

  @override
  State<DecibelPage> createState() => _DecibelPageState();
}

class _DecibelPageState extends State<DecibelPage> with SingleTickerProviderStateMixin {
  // 当前分贝值
  double _currentDecibel = 0.0;
  
  // 是否正在录制
  bool _isRecording = false;
  
  // 波形数据（用于可视化）
  final List<double> _waveformData = List.filled(50, 0.0);
  
  // 动画控制器
  late AnimationController _animationController;
  
  // 定时器（用于模拟音频数据）
  Timer? _recordingTimer;

  /// 是否已销毁，用于避免 dispose 过程中异步回调调用 setState
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat();
    
    _animationController.addListener(() {
      if (!_isDisposed && mounted && _isRecording) {
        setState(() {
          // 更新波形数据（模拟音频波形）
          _updateWaveform();
        });
      }
    });
  }
  
  @override
  void dispose() {
    _isDisposed = true;
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _animationController.dispose();
    _isRecording = false;
    _currentDecibel = 0.0;
    _waveformData.fillRange(0, _waveformData.length, 0.0);
    super.dispose();
  }
  
  // 更新波形数据（模拟音频波形）
  void _updateWaveform() {
    // 根据当前分贝值生成波形
    final baseAmplitude = (_currentDecibel / 120.0).clamp(0.0, 1.0);
    
    for (int i = 0; i < _waveformData.length; i++) {
      // 生成多频率的波形，模拟音频均衡器效果
      final t = i / _waveformData.length * 2 * math.pi;
      final wave1 = math.sin(t * 2 + _animationController.value * 2 * math.pi) * 0.3;
      final wave2 = math.sin(t * 4 + _animationController.value * 3 * math.pi) * 0.2;
      final wave3 = math.sin(t * 6 + _animationController.value * 4 * math.pi) * 0.1;
      
      _waveformData[i] = (baseAmplitude + wave1 + wave2 + wave3).clamp(0.0, 1.0);
    }
  }
  
  // 开始录制
  Future<void> _startRecording() async {
    // 请求麦克风权限
    final status = await Permission.microphone.request();
    
    if (status.isGranted && !_isDisposed && mounted) {
      setState(() {
        _isRecording = true;
      });
      
      // 开始模拟音频数据（实际应用中应该使用真实的音频录制）
      _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (!_isDisposed && mounted && _isRecording) {
          setState(() {
            // 模拟分贝值变化（实际应用中应该从音频数据计算）
            // 这里使用随机值模拟，实际应该从音频振幅计算
            final baseDecibel = 50.0 + math.sin(DateTime.now().millisecondsSinceEpoch / 1000.0) * 20.0;
            final noise = (math.Random().nextDouble() - 0.5) * 5.0;
            _currentDecibel = (baseDecibel + noise).clamp(0.0, 120.0);
          });
        }
      });
    } else {
      // 权限被拒绝
      if (!_isDisposed && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('需要麦克风权限才能测量分贝'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
  
  // 停止录制（用户点击停止时调用，dispose 中不再调用此方法）
  void _stopRecording() {
    _recordingTimer?.cancel();
    _recordingTimer = null;
    _isRecording = false;
    _currentDecibel = 0.0;
    _waveformData.fillRange(0, _waveformData.length, 0.0);
    if (!_isDisposed && mounted) {
      setState(() {});
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2A1B3D), // 深蓝紫色背景
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '测分贝',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w500,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            // 音频波形可视化
            Expanded(
              flex: 2,
              child: Center(
                child: _buildWaveformVisualization(),
              ),
            ),
            // 当前分贝值显示
            Expanded(
              flex: 1,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${_currentDecibel.toStringAsFixed(0)}db',
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      color: _getDecibelColor(_currentDecibel),
                      shadows: [
                        Shadow(
                          color: _getDecibelColor(_currentDecibel).withOpacity(0.5),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '当前分贝',
                    style: TextStyle(
                      fontSize: 16,
                      color: _getDecibelColor(_currentDecibel).withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            // 分贝等级说明（使用Flexible和SingleChildScrollView避免溢出）
            Flexible(
              flex: 2,
              child: SingleChildScrollView(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDecibelLevelItem('0-40db', '安静,舒适'),
                      const SizedBox(height: 6),
                      _buildDecibelLevelItem('40-60db', '一般,室内闲谈'),
                      const SizedBox(height: 6),
                      _buildDecibelLevelItem('60-70db', '普通吵闹,大声说话'),
                      const SizedBox(height: 6),
                      _buildDecibelLevelItem('70-90db', '很吵,神经系统不适'),
                      const SizedBox(height: 6),
                      _buildDecibelLevelItem('90-120db', '非常吵哦,可使听力受损'),
                    ],
                  ),
                ),
              ),
            ),
            // 开始/停止按钮
            Padding(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 4, bottom: 12),
              child: ElevatedButton(
                onPressed: _isRecording ? _stopRecording : _startRecording,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRecording ? Colors.red : Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: Text(
                  _isRecording ? '停止测量' : '开始测量',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // 构建波形可视化
  Widget _buildWaveformVisualization() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _WaveformPainter(_waveformData, _isRecording),
        );
      },
    );
  }
  
  // 构建分贝等级说明项
  Widget _buildDecibelLevelItem(String range, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          range,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            description,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
  
  // 获取分贝等级颜色
  Color _getDecibelColor(double decibel) {
    if (decibel < 40) {
      return Colors.green;
    } else if (decibel < 60) {
      return Colors.blue;
    } else if (decibel < 70) {
      return Colors.orange;
    } else if (decibel < 90) {
      return Colors.deepOrange;
    } else {
      return Colors.red;
    }
  }
}

// 波形绘制器
class _WaveformPainter extends CustomPainter {
  final List<double> waveformData;
  final bool isRecording;
  
  _WaveformPainter(this.waveformData, this.isRecording);
  
  @override
  void paint(Canvas canvas, Size size) {
    if (!isRecording) {
      return;
    }
    
    // 绘制多层波形（模拟音频均衡器效果）
    final layers = [
      {'color': Colors.orange, 'offset': 0.0, 'heightFactor': 1.0},
      {'color': Colors.amber, 'offset': 10.0, 'heightFactor': 0.8},
      {'color': Colors.yellow, 'offset': 20.0, 'heightFactor': 0.6},
      {'color': Colors.orange.shade300, 'offset': 30.0, 'heightFactor': 0.4},
    ];
    
    for (var layer in layers) {
      final paint = Paint()
        ..color = layer['color'] as Color
        ..style = PaintingStyle.fill;
      
      final offset = layer['offset'] as double;
      final heightFactor = layer['heightFactor'] as double;
      
      final barWidth = size.width / waveformData.length;
      final centerY = size.height / 2;
      
      for (int i = 0; i < waveformData.length; i++) {
        final x = i * barWidth;
        final amplitude = waveformData[i] * heightFactor;
        final barHeight = amplitude * size.height * 0.8;
        
        // 绘制上下对称的波形
        canvas.drawRect(
          Rect.fromLTWH(
            x + offset,
            centerY - barHeight / 2,
            barWidth - 2,
            barHeight,
          ),
          paint,
        );
      }
    }
  }
  
  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.waveformData != waveformData || oldDelegate.isRecording != isRecording;
  }
}

