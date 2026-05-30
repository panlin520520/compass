import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_config.dart';

class CompassDisplayPage extends StatelessWidget {
  final String compassImageBase64;
  final String? compassImageUrl;
  final String sittingText;
  final String facingText;
  final String sittingDetail;
  final String facingDetail;
  final double? sittingDegree;
  final double? facingDegree;
  final String address;

  const CompassDisplayPage({
    super.key,
    this.compassImageBase64 = '',
    this.compassImageUrl,
    required this.sittingText,
    required this.facingText,
    required this.sittingDetail,
    required this.facingDetail,
    this.sittingDegree,
    this.facingDegree,
    required this.address,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE53935), // 红色背景
              Color(0xFFC62828),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 顶部导航栏
              _buildAppBar(context),
              
              // 主要内容
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      
                      // 方向信息
                      _buildDirectionInfo(),
                      
                      const SizedBox(height: 30),
                      
                      // 罗盘图片
                      _buildCompassImage(),
                      
                      const SizedBox(height: 30),
                      
                      // 地址信息
                      _buildAddressInfo(),
                      
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(
              Icons.arrow_back_ios_new,
              color: Colors.white,
              size: 20,
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                '测量结果',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 48), // 占位保持居中
        ],
      ),
    );
  }

  Widget _buildDirectionInfo() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // 向信息
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                facingDetail.isNotEmpty ? facingDetail : facingText,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD32F2F),
                ),
              ),
              if (facingDegree != null) ...[
                const SizedBox(width: 8),
                Text(
                  '${facingDegree!.toStringAsFixed(1)}°',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFD32F2F),
                  ),
                ),
              ],
            ],
          ),
          
          const SizedBox(height: 12),
          
          // 坐信息
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                sittingDetail.isNotEmpty ? sittingDetail : sittingText,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1976D2),
                ),
              ),
              if (sittingDegree != null) ...[
                const SizedBox(width: 8),
                Text(
                  '${sittingDegree!.toStringAsFixed(1)}°',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1976D2),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompassImage() {
    if (compassImageUrl != null && compassImageUrl!.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              color: Colors.white,
              child: AppAssetImage(
                assetPath: compassImageUrl!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Text(
                      '图片加载失败',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    if (compassImageBase64.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        height: 300,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: Text(
            '罗盘图片不可用',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 16,
            ),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: 1.0,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
            ),
            child: Image.memory(
              base64Decode(compassImageBase64),
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Text(
                    '图片加载失败',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddressInfo() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(
            Icons.location_on,
            color: Color(0xFFD32F2F),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              address.isNotEmpty ? address : '未知位置',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
