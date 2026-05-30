import 'dart:math' show pi;

/// Returns extra initial rotation (in radians) for certain assets.
///
/// Applied on top of the compass dial base rotation (`-heading + π/2`).
double extraInitialRotationForAsset(String assetPath) {
  final normalized = assetPath.replaceAll('\\', '/');

  // 简易盘·廿四方位：盘面印刷相对磁北方位刻度整体偏转 90°，此处只做盘面顺时针补偿；
  // 顶部度数仍用磁方位（与指南针页一致），不再对文字做 +90°。
  if (normalized.contains('1-SimplePlate-TwentyFourDirection')) {
    return 90.0 * pi / 180.0;
  }

  // 入门盘：盘面印刷相对默认朝向偏转 180°，顺时针补偿
  if (normalized.contains('2-BeginnerPlate')) {
    return 180.0 * pi / 180.0;
  }

  // `assets/{black,gold,white}/10-LongmenBaju.png`：14.5° 顺时针补偿
  if (!normalized.endsWith('/10-LongmenBaju.png')) return 0.0;

  final isTargetFolder = normalized.contains('assets/black/') ||
      normalized.contains('assets/gold/') ||
      normalized.contains('assets/white/');

  if (!isTargetFolder) return 0.0;

  return 14.5 * pi / 180.0;
}

/// 中心指针 [assets/luopanzhizhen.png] 在 PNG 中 **水平放置**，
/// **右端（带双缺口的粗针）为北端**，默认朝向 +X。
///
/// 盘面随 `[-heading + π/2]` 转；指针相对屏幕始终指向磁北：
/// `rotation = -π/2 - heading`（弧度）。
double luopanNeedleRotationRadians(double magneticHeadingDeg) {
  var h = magneticHeadingDeg % 360;
  if (h < 0) h += 360;
  return -pi / 2 - h * pi / 180.0;
}

// --- 二十四山坐向与兼向（247° 起算，每 15° 一山）---

const kTwentyFourMountains = [
  '庚', '酉', '辛', '戌', '乾', '亥', '壬', '子', '癸', '丑', '艮', '寅',
  '甲', '卯', '乙', '辰', '巽', '巳', '丙', '午', '丁', '未', '坤', '申',
];

double _normalizeMountainHeading(double heading) {
  var h = heading % 360;
  if (h < 0) h += 360;
  return h;
}

int mountainIndex(double heading) {
  final normalized = _normalizeMountainHeading(heading);
  var offset = normalized - 247.0;
  if (offset < 0) offset += 360;
  return (offset / 15).floor() % 24;
}

String mountainAt(double heading) =>
    kTwentyFourMountains[mountainIndex(heading)];

String oppositeMountainAt(double heading) => mountainAt(heading + 180);

String jianSuffix(double heading) {
  final normalized = _normalizeMountainHeading(heading);
  var offset = normalized - 247.0;
  if (offset < 0) offset += 360;
  final offsetInSegment = offset % 15;
  if (offsetInSegment <= 7.5) return '';

  final facingIdx = mountainIndex(heading);
  final sittingIdx = (facingIdx + 12) % 24;
  final sittingAdjIdx = (sittingIdx + 1) % 24;
  final facingAdjIdx = (facingIdx + 1) % 24;
  return '${kTwentyFourMountains[sittingAdjIdx]}${kTwentyFourMountains[facingAdjIdx]}';
}

String formatMountainFacing(double heading) {
  final facing = mountainAt(heading);
  final sitting = oppositeMountainAt(heading);
  final jian = jianSuffix(heading);
  final base = '$sitting山$facing向';
  if (jian.isEmpty) return base;
  return '$base兼$jian';
}

String formatSittingDetail(double heading) {
  final sitting = oppositeMountainAt(heading);
  final jian = jianSuffix(heading);
  if (jian.isEmpty) return '$sitting山';
  return '$sitting山兼${jian[0]}';
}

String formatFacingDetail(double heading) {
  final facing = mountainAt(heading);
  final jian = jianSuffix(heading);
  if (jian.isEmpty) return '$facing向';
  return '$facing向兼${jian[1]}';
}

// --- 八宅（与 assets/bazaixianhoutianluoshushu.json 度数区间一致）---

const _bazhaiRanges = <({double minDeg, double maxDeg, String gua})>[
  (minDeg: 337.5, maxDeg: 22.5, gua: '坎'),
  (minDeg: 22.5, maxDeg: 67.5, gua: '艮'),
  (minDeg: 67.5, maxDeg: 112.5, gua: '震'),
  (minDeg: 112.5, maxDeg: 157.5, gua: '巽'),
  (minDeg: 157.5, maxDeg: 202.5, gua: '离'),
  (minDeg: 202.5, maxDeg: 247.5, gua: '坤'),
  (minDeg: 247.5, maxDeg: 292.5, gua: '兑'),
  (minDeg: 292.5, maxDeg: 337.5, gua: '乾'),
];

bool _headingInBazhaiRange(double heading, double minDeg, double maxDeg) {
  if (minDeg <= maxDeg) {
    return heading >= minDeg && heading < maxDeg;
  }
  return heading >= minDeg || heading < maxDeg;
}

String? bazhaiGuaForFacingHeading(double facingHeadingDeg) {
  var sitting = (facingHeadingDeg + 180) % 360;
  if (sitting < 0) sitting += 360;
  for (final range in _bazhaiRanges) {
    if (_headingInBazhaiRange(sitting, range.minDeg, range.maxDeg)) {
      return range.gua;
    }
  }
  return null;
}

/// 首页八宅标签，如「坎宅」。
String formatBazhaiZhaiLabel(double facingHeadingDeg) {
  final gua = bazhaiGuaForFacingHeading(facingHeadingDeg);
  if (gua == null || gua.isEmpty) return '';
  return '$gua宅';
}