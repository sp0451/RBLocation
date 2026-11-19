import Flutter
import UIKit

@MainActor
public class LocationBridgePlugin: NSObject, @preconcurrency FlutterPlugin {
  private static var runtime: LocationRuntime?
  public static func register(with registrar: FlutterPluginRegistrar) {
    // Runtime lifetime is independent of Flutter page/controller attach and detach.
    let instance = LocationRuntime(messenger: registrar.messenger())
    runtime = instance
    NativeLocationApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)
    registrar.addApplicationDelegate(LocationBridgePlugin())
  }
}
