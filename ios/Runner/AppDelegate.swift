import Flutter
import Photos
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "liji_image_saver",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "saveImageToGallery":
        LijiImageSaver.handleSaveImageToGallery(call: call, result: result)
      case "shareImage":
        LijiImageSaver.handleShareImage(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

private enum LijiImageSaver {
  static func handleSaveImageToGallery(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let typedData = args["imageBytes"] as? FlutterStandardTypedData,
          let image = UIImage(data: typedData.data) else {
      result(false)
      return
    }

    let saveBlock = {
      PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.creationRequestForAsset(from: image)
      }, completionHandler: { success, _ in
        DispatchQueue.main.async {
          result(success)
        }
      })
    }

    let onAuthorized: (PHAuthorizationStatus) -> Void = { status in
      switch status {
      case .authorized, .limited:
        saveBlock()
      default:
        DispatchQueue.main.async {
          result(false)
        }
      }
    }

    if #available(iOS 14, *) {
      let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
      switch current {
      case .notDetermined:
        PHPhotoLibrary.requestAuthorization(for: .addOnly, handler: onAuthorized)
      default:
        onAuthorized(current)
      }
    } else {
      let current = PHPhotoLibrary.authorizationStatus()
      switch current {
      case .notDetermined:
        PHPhotoLibrary.requestAuthorization(onAuthorized)
      default:
        onAuthorized(current)
      }
    }
  }

  static func handleShareImage(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let typedData = args["imageBytes"] as? FlutterStandardTypedData,
          let image = UIImage(data: typedData.data) else {
      result(false)
      return
    }

    DispatchQueue.main.async {
      guard let presenter = topViewController() else {
        result(false)
        return
      }

      let activityVC = UIActivityViewController(
        activityItems: [image],
        applicationActivities: nil
      )
      if let popover = activityVC.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(
          x: presenter.view.bounds.midX,
          y: presenter.view.bounds.midY,
          width: 0,
          height: 0
        )
        popover.permittedArrowDirections = []
      }

      presenter.present(activityVC, animated: true) {
        result(true)
      }
    }
  }

  private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
    let root = base ?? UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
      .first(where: { $0.isKeyWindow })?
      .rootViewController

    if let navigation = root as? UINavigationController {
      return topViewController(base: navigation.visibleViewController)
    }
    if let tab = root as? UITabBarController {
      return topViewController(base: tab.selectedViewController)
    }
    if let presented = root?.presentedViewController {
      return topViewController(base: presented)
    }
    return root
  }
}
