import 'package:flutter/services.dart';

/// Open external apps/URLs via Android MethodChannel (no url_launcher package).
class ExternalUrlLauncher {
  ExternalUrlLauncher._();

  static const MethodChannel _channel = MethodChannel('compass_app_utils');

  static Future<bool> canOpenUrl(Uri uri) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'canOpenUrl',
        <String, dynamic>{'url': uri.toString()},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> openUrl(Uri uri) async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'openUrl',
        <String, dynamic>{'url': uri.toString()},
      );
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
