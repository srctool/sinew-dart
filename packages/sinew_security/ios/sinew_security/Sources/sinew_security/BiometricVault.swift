import Foundation
import LocalAuthentication
import Security

enum Availability: String {
  case available, notEnrolled, unavailable
}

/// The names are Dart's `BiometricFailure` values, read with `byName`.
enum Failure: String {
  case cancelled, lockedOut, invalidated, unavailable
}

enum Unlock {
  case unlocked(String)
  case failed(Failure)
}

/// The secret is a Keychain generic-password item (`service` = the alias, `account` = "secret") with
/// `biometryCurrentSet` access control: readable only after a match by a face or finger enrolled when it was stored,
/// on this device, while a passcode is set. Reading it shows the system prompt; adding it doesn't. The flows are
/// Kotlin's `sinew-security` vault. Calls block (a read waits for the prompt), so the plugin runs them off the main
/// thread, one at a time.
final class BiometricVault {
  private var installChecked = Set<String>()

  func availability() -> Availability {
    var error: NSError?
    if LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) { return .available }
    return error?.code == LAError.biometryNotEnrolled.rawValue ? .notEnrolled : .unavailable
  }

  func isStored(_ alias: String, clearOnReinstall: Bool) -> Bool {
    clearAfterReinstall(alias, clearOnReinstall)
    let context = LAContext()
    context.interactionNotAllowed = true  // answers without a prompt
    var query = itemQuery(alias)
    query[kSecUseAuthenticationContext as String] = context
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    return status == errSecSuccess || status == errSecInteractionNotAllowed
  }

  /// Stores `secret` without a prompt, returning `nil`, or why not.
  func store(_ alias: String, clearOnReinstall: Bool, secret: String) -> Failure? {
    clearAfterReinstall(alias, clearOnReinstall)
    guard availability() == .available,
      let access = SecAccessControlCreateWithFlags(
        nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, nil)
    else { return .unavailable }
    delete(alias)
    var query = itemQuery(alias)
    query[kSecAttrAccessControl as String] = access
    query[kSecValueData as String] = Data(secret.utf8)
    return SecItemAdd(query as CFDictionary, nil) == errSecSuccess ? nil : .unavailable
  }

  func unlock(_ alias: String, clearOnReinstall: Bool, reason: String) -> Unlock {
    clearAfterReinstall(alias, clearOnReinstall)
    let context = LAContext()
    context.localizedReason = reason
    var query = itemQuery(alias)
    query[kSecUseAuthenticationContext as String] = context
    query[kSecReturnData as String] = true
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)  // blocks until the prompt is answered
    if status == errSecSuccess, let data = result as? Data {
      return .unlocked(String(decoding: data, as: UTF8.self))
    }
    switch status {
    case errSecUserCanceled: return .failed(.cancelled)
    case errSecItemNotFound: return .failed(.invalidated)  // nothing stored, or the enrollment changed
    default: return .failed(lockedOut() ? .lockedOut : failureOf(status: status))
    }
  }

  func disable(_ alias: String, clearOnReinstall: Bool) {
    clearAfterReinstall(alias, clearOnReinstall)
    delete(alias)
  }

  /// For the device tests: the item's protection class (`pdmn`) and access control (`accc`), read without a prompt.
  func debugState(_ alias: String) -> [String: String] {
    let context = LAContext()
    context.interactionNotAllowed = true
    var query = itemQuery(alias)
    query[kSecUseAuthenticationContext as String] = context
    query[kSecReturnAttributes as String] = true
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let attributes = result as? [String: Any]
    else { return [:] }
    return ["pdmn", "accc"].reduce(into: [:]) { state, key in
      if let value = attributes[key] { state[key] = String(describing: value) }
    }
  }

  /// For the device tests: deletes the install marker, as an uninstall does.
  func debugRemoveInstallMarker(_ alias: String) {
    InstallMarker("biometric.\(alias)").remove()
    installChecked.remove(alias)
  }

  /// On the first use after an install, deletes the item a previous install left behind.
  private func clearAfterReinstall(_ alias: String, _ clearOnReinstall: Bool) {
    guard clearOnReinstall, !installChecked.contains(alias) else { return }
    if InstallMarker("biometric.\(alias)").claim() { delete(alias) }
    installChecked.insert(alias)
  }

  private func delete(_ alias: String) {
    SecItemDelete(itemQuery(alias) as CFDictionary)
  }

  private func lockedOut() -> Bool {
    var error: NSError?
    return !LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
      && error?.code == LAError.biometryLockout.rawValue
  }

  private func itemQuery(_ alias: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: alias,
      kSecAttrAccount as String: "secret",
    ]
  }
}

/// What an `OSStatus` other than success, a cancel or a missing item means for the caller.
func failureOf(status: OSStatus) -> Failure {
  status == errSecInteractionNotAllowed ? .unavailable : .cancelled  // errSecAuthFailed: no match, prompt dismissed
}

/// A marker file in Application Support, which an uninstall deletes while the Keychain keeps its items. Each owner has
/// its own marker, so one owner claiming it never hides a reinstall from another.
struct InstallMarker {
  private let url: URL

  init(_ name: String) {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    url = support.appendingPathComponent("sinew/installed/\(name)")
  }

  /// `true` the first time it's called since the app was installed: the marker didn't exist, and now does.
  func claim() -> Bool {
    let files = FileManager.default
    if files.fileExists(atPath: url.path) { return false }
    try? files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    files.createFile(atPath: url.path, contents: nil)
    return true
  }

  func remove() {
    try? FileManager.default.removeItem(at: url)
  }
}
