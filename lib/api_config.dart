import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

/// 后端接口基础地址，统一在此配置
///
/// 修改服务器地址时，只需要改这里一处即可。
const String kApiBaseUrl = 'http://112.124.9.121:8066';
// const String kApiBaseUrl = 'http://192.168.1.2:8066';

/// 静态资源加载方式
///
/// - `false`（默认）：从 App 包内 `assets/` 读取，无网络延迟，推荐日常使用。
/// - `true`：从后端 `{kApiBaseUrl}/app-assets/` 读取，便于热更新资源、减小安装包。
const bool kUseRemoteAppAssets = false;

/// 忘记密码提交接口（POST，表单字段与注册一致：`phoneNumber`、`password`、`smsCode`）。
/// 若服务端路径不同，只改此处即可，例如 `cp/forgotPassword`。
const String kCpResetPasswordPath = 'cp/resetPassword';

/// 事项记录：列表 GET、新增 POST、删除 DELETE（路径前缀 cp/matterRecord）

/// 后端静态资源 URL 路径段（对应 Spring Boot `/app-assets/**`）
const String kAppAssetsUrlSegment = 'app-assets';

/// 去掉逻辑路径前缀，得到相对路径（如 gold/foo.png）。
/// 入参可为 `assets/...`、`app-assets/...` 或 `gold/foo.png`。
String normalizeAssetPath(String path) {
  var p = path.replaceAll('\\', '/');
  if (p.startsWith('/')) p = p.substring(1);
  if (p.startsWith('$kAppAssetsUrlSegment/')) {
    return p.substring(kAppAssetsUrlSegment.length + 1);
  }
  if (p.startsWith('assets/')) {
    return p.substring('assets/'.length);
  }
  return p;
}

/// 从路径或完整 URL 解析出包内资源路径，如 `assets/gold/a.png`。
String toBundleAssetPath(String pathOrUrl) {
  final p = pathOrUrl.trim();
  if (p.isEmpty) return p;
  if (p.startsWith('http://') || p.startsWith('https://')) {
    final uri = Uri.parse(fixLegacyAssetsInUrl(p));
    final segments = uri.pathSegments;
    final appIdx = segments.indexOf(kAppAssetsUrlSegment);
    if (appIdx >= 0 && appIdx < segments.length - 1) {
      return 'assets/${segments.sublist(appIdx + 1).join('/')}';
    }
    final assetsIdx = segments.indexOf('assets');
    if (assetsIdx >= 0 && assetsIdx < segments.length - 1) {
      return 'assets/${segments.sublist(assetsIdx + 1).join('/')}';
    }
  }
  final relative = normalizeAssetPath(p);
  return relative.isEmpty ? p : 'assets/$relative';
}

/// 转为后端静态资源完整 URL，统一使用 `/app-assets/`。
///
/// 例：`assets/gold/a.png` 或 `app-assets/gold/a.png`
/// → `{kApiBaseUrl}/app-assets/gold/a.png`
String appAssetUrl(String assetPath) {
  final relative = normalizeAssetPath(assetPath);
  final encoded =
      relative.split('/').map((segment) => Uri.encodeComponent(segment)).join('/');
  return '$kApiBaseUrl/$kAppAssetsUrlSegment/$encoded';
}

/// 将历史 URL 中的 `/assets/` 修正为 `/app-assets/`（仅路径段，避免误替换文件名）
String fixLegacyAssetsInUrl(String url) {
  final uri = Uri.parse(url);
  final path = uri.path;
  if (!path.contains('/assets/') || path.contains('/$kAppAssetsUrlSegment/')) {
    return url;
  }
  final newPath = path.replaceFirst('/assets/', '/$kAppAssetsUrlSegment/');
  return uri.replace(path: newPath).toString();
}

/// 解析为可加载的地址：远程模式返回 http URL；本地模式返回 `assets/...` 包路径。
String resolveAssetUrl(String pathOrUrl) {
  final p = pathOrUrl.trim();
  if (p.isEmpty) return p;
  if (!kUseRemoteAppAssets) {
    return toBundleAssetPath(p);
  }
  if (p.startsWith('http://') || p.startsWith('https://')) {
    return fixLegacyAssetsInUrl(p);
  }
  return appAssetUrl(p);
}

/// 保存测量记录等场景：远程模式存完整 URL，本地模式存 `assets/...` 逻辑路径。
String storageAssetReference(String assetPath) {
  if (kUseRemoteAppAssets) {
    return appAssetUrl(assetPath);
  }
  return toBundleAssetPath(assetPath);
}

ImageProvider appAssetImageProvider(String assetPath) {
  if (kUseRemoteAppAssets) {
    return NetworkImage(resolveAssetUrl(assetPath));
  }
  return AssetImage(toBundleAssetPath(assetPath));
}

Future<String?> loadAppAssetString(String assetPath) async {
  if (!kUseRemoteAppAssets) {
    try {
      return await rootBundle.loadString(toBundleAssetPath(assetPath));
    } catch (_) {
      return null;
    }
  }
  try {
    final resp = await http
        .get(Uri.parse(appAssetUrl(assetPath)))
        .timeout(const Duration(seconds: 30));
    if (resp.statusCode != 200) return null;
    return utf8.decode(resp.bodyBytes);
  } catch (_) {
    return null;
  }
}

Future<Uint8List?> loadAppAssetBytes(String assetPath) async {
  if (!kUseRemoteAppAssets) {
    try {
      final data = await rootBundle.load(toBundleAssetPath(assetPath));
      return data.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
  try {
    final resp = await http
        .get(Uri.parse(appAssetUrl(assetPath)))
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) return null;
    return resp.bodyBytes;
  } catch (_) {
    return null;
  }
}

/// 获取资源图片尺寸（用于布局计算）。
Future<Size> getAppAssetImageSize(String assetPath) async {
  final bytes = await loadAppAssetBytes(assetPath);
  if (bytes == null || bytes.isEmpty) return Size.zero;
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final size = Size(image.width.toDouble(), image.height.toDouble());
  image.dispose();
  return size;
}

/// 加载 [assetPath] 对应资源图（本地 assets 或后端 app-assets，由 [kUseRemoteAppAssets] 决定）。
class AppAssetImage extends StatelessWidget {
  const AppAssetImage({
    super.key,
    required this.assetPath,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.color,
    this.colorBlendMode,
    this.opacity,
    this.filterQuality = FilterQuality.low,
    this.errorBuilder,
    this.loadingBuilder,
  });

  final String assetPath;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final Color? color;
  final BlendMode? colorBlendMode;
  final Animation<double>? opacity;
  final FilterQuality filterQuality;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;

  Widget _errorWidget(BuildContext context, Object error, StackTrace? stackTrace) {
    return errorBuilder?.call(context, error, stackTrace) ??
        SizedBox(
          width: width,
          height: height,
          child: const Icon(Icons.broken_image_outlined, size: 24),
        );
  }

  @override
  Widget build(BuildContext context) {
    if (!kUseRemoteAppAssets) {
      return Image.asset(
        toBundleAssetPath(assetPath),
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        color: color,
        colorBlendMode: colorBlendMode,
        opacity: opacity,
        filterQuality: filterQuality,
        errorBuilder: _errorWidget,
      );
    }

    return Image.network(
      resolveAssetUrl(assetPath),
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      color: color,
      colorBlendMode: colorBlendMode,
      opacity: opacity,
      filterQuality: filterQuality,
      errorBuilder: _errorWidget,
      loadingBuilder: loadingBuilder ??
          (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return SizedBox(
              width: width,
              height: height,
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
    );
  }
}
