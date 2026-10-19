import Flutter

/// The channel side of `ChannelBiometricVault` in Dart: one `BiometricVault` serves every alias, one call at a time,
/// on a serial queue (a read blocks while its prompt is up).
public final class SinewSecurityPlugin: NSObject, FlutterPlugin {
  private let vault = BiometricVault()
  private let queue = DispatchQueue(label: "com.srctool.sinew.biometric_vault")

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.srctool.sinew/biometric_vault", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(SinewSecurityPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    let alias = args["alias"] as? String ?? ""
    let clear = args["clearOnReinstall"] as? Bool ?? true
    queue.async { [vault] in
      let value: Any?
      switch call.method {
      case "availability": value = vault.availability().rawValue
      case "isStored": value = vault.isStored(alias, clearOnReinstall: clear)
      case "store":
        value = vault.store(alias, clearOnReinstall: clear, secret: args["secret"] as? String ?? "")?.rawValue
      case "unlock":
        switch vault.unlock(alias, clearOnReinstall: clear, reason: args["reason"] as? String ?? "") {
        case .unlocked(let secret): value = ["secret": secret]
        case .failed(let failure): value = ["failure": failure.rawValue]
        }
      case "disable":
        vault.disable(alias, clearOnReinstall: clear)
        value = nil
      case "debugState": value = vault.debugState(alias)
      case "debugRemoveInstallMarker":
        vault.debugRemoveInstallMarker(alias)
        value = nil
      default: value = FlutterMethodNotImplemented
      }
      DispatchQueue.main.async { result(value) }
    }
  }
}
