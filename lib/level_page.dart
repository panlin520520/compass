import 'package:flutter/material.dart';
import 'api_config.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:math' as math;
import 'dart:async';

class LevelPage extends StatefulWidget {
  const LevelPage({super.key});

  @override
  State<LevelPage> createState() => _LevelPageState();
}

class _LevelPageState extends State<LevelPage> with SingleTickerProviderStateMixin {
  // 设备倾斜角度（度）
  double _pitch = 0.0; // 前后倾斜（X轴）
  double _roll = 0.0; // 左右倾斜（Y轴）
  
  // 平滑处理用的目标值
  double _targetPitch = 0.0;
  double _targetRoll = 0.0;
  
  // 动画控制器用于平滑过渡
  late AnimationController _animationController;
  
  // 传感器事件流
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  
  @override
  void initState() {
    super.initState();
    // 初始化动画控制器用于平滑过渡
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    )..repeat();
    
    _animationController.addListener(() {
      if (mounted) {
        setState(() {
          // 使用线性插值平滑过渡到目标值
          _pitch = _smoothValue(_pitch, _targetPitch);
          _roll = _smoothValue(_roll, _targetRoll);
        });
      }
    });
    
    _startAccelerometer();
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    _stopAccelerometer();
    super.dispose();
  }
  
  // 平滑值函数（低通滤波器）
  double _smoothValue(double current, double target) {
    // 使用0.15的平滑系数，值越小越平滑但响应越慢
    return current + (target - current) * 0.15;
  }
  
  // 启动加速度计
  void _startAccelerometer() {
    _accelerometerSubscription = accelerometerEventStream().listen(
      (AccelerometerEvent event) {
        // 计算倾斜角度（直接转换为角度）
        // pitch: 前后倾斜（绕X轴旋转）
        // roll: 左右倾斜（绕Y轴旋转）
        // 使用与 compass_detail_page.dart 相同的计算方法
        final pitch = math.atan2(event.y, math.sqrt(event.x * event.x + event.z * event.z)) * (180 / math.pi);
        final roll = math.atan2(-event.x, event.z) * (180 / math.pi);
        
        // 更新目标值，平滑处理在动画控制器中完成
        _targetPitch = pitch;
        _targetRoll = roll;
      },
      onError: (error) {
        print('加速度计错误: $error');
      },
    );
  }
  
  // 停止加速度计
  void _stopAccelerometer() {
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
  }
  
  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;
    
    // 计算垂直水平仪的高度（用于与水平水平仪长度一致）
    final verticalLevelHeight = screenHeight - 120 - 100; // top: 120, bottom: 100
    final verticalLevelWidth = 80.0;
    // 水平水平仪长度：使用垂直水平仪高度，但不大于屏幕宽度的60%，防止超出屏幕
    final horizontalLevelLength = math.min(verticalLevelHeight, screenWidth * 0.6);
    
    // 角度已经在传感器中计算好了
    final pitchDegrees = _pitch;
    final rollDegrees = _roll;
    
    return Scaffold(
      backgroundColor: Colors.grey[300],
      appBar: AppBar(
        title: const Text('水平仪'),
        backgroundColor: Colors.grey[300],
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // 水平气泡水平仪（顶部，长度与垂直水平仪高度一致，但不超出屏幕）
            Positioned(
              top: 20,
              left: 20,
              width: horizontalLevelLength,
              height: 80,
              child: _buildHorizontalLevel(rollDegrees),
            ),
            // 垂直气泡水平仪（左侧，在水平仪下方）
            Positioned(
              top: 120,
              left: 20,
              width: verticalLevelWidth,
              bottom: 100,
              child: _buildVerticalLevel(pitchDegrees),
            ),
            // 圆形水平仪（右下区域，居中，增大尺寸）
            Positioned(
              top: 120,
              left: 120,
              right: 20,
              bottom: 100,
              child: Center(
                child: SizedBox(
                  width: math.min(screenWidth * 0.6, (screenHeight - 120 - 100) * 0.9),
                  height: math.min(screenWidth * 0.6, (screenHeight - 120 - 100) * 0.9),
                  child: _buildBullseyeLevel(pitchDegrees, rollDegrees),
                ),
              ),
            ),
            // 数字角度显示（底部居中）
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              height: 60,
              child: Center(
                child: _buildAngleDisplay(pitchDegrees, rollDegrees),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 构建水平气泡水平仪
  Widget _buildHorizontalLevel(double rollDegrees) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final centerX = width / 2;
        final bubbleWidth = 70.0;
        final bubbleHalfWidth = bubbleWidth / 2;
        
        // 根据容器宽度和气泡宽度动态计算最大偏移量
        // 确保气泡不会超出容器边界：centerX + maxOffset - bubbleHalfWidth >= 0
        // 和 centerX + maxOffset + bubbleHalfWidth <= width
        final maxOffset = (width / 2 - bubbleHalfWidth - 5).clamp(0.0, double.infinity);
        
        // 计算气泡位置（像素偏移，每度约3像素）
        final bubbleOffset = rollDegrees * 3.0;
        final clampedOffset = bubbleOffset.clamp(-maxOffset, maxOffset);
        
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              // 背景图片
              Positioned.fill(
                child: AppAssetImage(
                  assetPath:
                  'assets/shuipingyi/Tp.png',
                  fit: BoxFit.fill,
                ),
              ),
              // 气泡图片
              Positioned(
                left: centerX + clampedOffset - bubbleHalfWidth,
                top: 0,
                bottom: 0,
                child: AppAssetImage(
                  assetPath:
                  'assets/shuipingyi/Vv.png',
                  width: bubbleWidth,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  // 构建垂直气泡水平仪
  Widget _buildVerticalLevel(double pitchDegrees) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final centerY = height / 2;
        final bubbleHeight = 30.0;
        final bubbleHalfHeight = bubbleHeight / 2;
        
        // 根据容器高度和气泡高度动态计算最大偏移量
        // 确保气泡能抵拢上下边沿：centerY + maxOffset + bubbleHalfHeight <= height
        // 和 centerY - maxOffset - bubbleHalfHeight >= 0
        final maxOffset = (height / 2 - bubbleHalfHeight - 2).clamp(0.0, double.infinity);
        
        // 计算气泡位置（像素偏移，每度约3像素，注意Y轴方向相反）
        final bubbleOffset = -pitchDegrees * 3.0;
        final clampedOffset = bubbleOffset.clamp(-maxOffset, maxOffset);
        
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
          child: Stack(
            children: [
              // 背景图片
              Positioned.fill(
                child: AppAssetImage(
                  assetPath:
                  'assets/shuipingyi/-v.png',
                  fit: BoxFit.fill,
                ),
              ),
              // 气泡（保持原有逻辑，如果需要的话可以后续替换为图片）
              Positioned(
                top: centerY + clampedOffset - bubbleHalfHeight,
                left: width * 0.2,
                right: width * 0.2,
                child: Container(
                  height: bubbleHeight,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.2),
                    border: Border.all(color: Colors.black, width: 1),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  // 构建圆形水平仪
  Widget _buildBullseyeLevel(double pitchDegrees, double rollDegrees) {
    // 计算气泡在圆形中的位置（像素偏移）
    final bubbleX = rollDegrees * 3.0;
    final bubbleY = -pitchDegrees * 3.0; // 注意Y轴方向相反
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth;
        final centerX = size / 2;
        final centerY = size / 2;
        final maxRadius = size / 2 - 20; // 最大移动半径
        
        // 限制气泡在圆形范围内
        final distance = math.sqrt(bubbleX * bubbleX + bubbleY * bubbleY);
        final clampedDistance = distance.clamp(0.0, maxRadius);
        final angle = math.atan2(bubbleY, bubbleX);
        final finalX = clampedDistance * math.cos(angle);
        final finalY = clampedDistance * math.sin(angle);
        
        return Container(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
          ),
          child: Stack(
            children: [
              // 背景图片 vF.png
              Positioned.fill(
                child: ClipOval(
                  child: AppAssetImage(
                  assetPath:
                    'assets/shuipingyi/vF.png',
                    fit: BoxFit.fill,
                  ),
                ),
              ),
              // 背景图片 kR.png（重叠在vF.png上方）
              Positioned.fill(
                child: ClipOval(
                  child: AppAssetImage(
                  assetPath:
                    'assets/shuipingyi/kR.png',
                    fit: BoxFit.fill,
                  ),
                ),
              ),
              // 气泡图片
              Positioned(
                left: centerX + finalX - 15,
                top: centerY + finalY - 15,
                child: AppAssetImage(
                  assetPath:
                  'assets/shuipingyi/gs.png',
                  width: 30,
                  height: 30,
                  fit: BoxFit.contain,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  
  // 构建角度显示
  Widget _buildAngleDisplay(double pitchDegrees, double rollDegrees) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[600],
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Text(
            'X: ${pitchDegrees.toStringAsFixed(1)}°',
            style: const TextStyle(
              fontSize: 20,
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Y: ${rollDegrees.toStringAsFixed(1)}°',
            style: const TextStyle(
              fontSize: 20,
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// 虚线圆环绘制器
class _DashedCirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    
    final center = Offset(size.width / 2, size.height / 2);
    const radius = 30.0;
    
    // 绘制虚线圆（使用多个小段）
    const dashCount = 24;
    const dashAngle = 2 * math.pi / dashCount;
    
    for (int i = 0; i < dashCount; i += 2) {
      final startAngle = i * dashAngle;
      
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        dashAngle,
        false,
        paint,
      );
    }
  }
  
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

