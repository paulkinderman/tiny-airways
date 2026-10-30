import Flutter
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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ICloudSave") {
      ICloudSave.register(with: registrar)
    }
  }
}

/// The save's cloud copy in iCloud's key-value store, for
/// `lib/app/icloud_save_store.dart`. Needs the
/// `com.apple.developer.ubiquity-kvstore-identifier` entitlement
/// (Runner.entitlements); without an iCloud account it reports unavailable.
class ICloudSave: NSObject, FlutterPlugin {
  private static let key = "save"

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "tiny_airways/icloud", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(ICloudSave(), channel: channel)
    NSUbiquitousKeyValueStore.default.synchronize()
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let store = NSUbiquitousKeyValueStore.default
    switch call.method {
    case "isAvailable":
      result(FileManager.default.ubiquityIdentityToken != nil)
    case "read":
      store.synchronize()
      result(store.string(forKey: ICloudSave.key))
    case "write":
      guard let text = call.arguments as? String else {
        result(FlutterError(code: "bad_args", message: "write needs a string", details: nil))
        return
      }
      store.set(text, forKey: ICloudSave.key)
      store.synchronize()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
