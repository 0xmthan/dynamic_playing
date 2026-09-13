import Foundation

struct ScriptError: Error {
    var code: Int
    var message: String

    var isAuthorizationFailure: Bool { code == -1743 || code == -600 }
}

nonisolated enum AppleScriptBridge {
    private static let queue = DispatchQueue(label: "dev.mthan.dynamic-playing.applescript", qos: .userInitiated)

    static func text(_ source: String) async -> Result<String, ScriptError> {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: textSync(source)) }
        }
    }

    static func imageData(_ source: String) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: imageDataSync(source)) }
        }
    }

    static func fire(_ source: String) {
        queue.async { _ = textSync(source) }
    }

    private static func textSync(_ source: String) -> Result<String, ScriptError> {
        switch execute(source) {
        case .success(let descriptor): return .success(descriptor.stringValue ?? "")
        case .failure(let error): return .failure(error)
        }
    }

    private static func imageDataSync(_ source: String) -> Data? {
        guard case .success(let descriptor) = execute(source) else { return nil }

        if descriptor.descriptorType == typeUnicodeText || descriptor.descriptorType == typeUTF8Text {
            return nil
        }
        let data = descriptor.data
        return data.count > 128 ? data : nil
    }

    private static func execute(_ source: String) -> Result<NSAppleEventDescriptor, ScriptError> {
        guard let script = NSAppleScript(source: source) else {
            return .failure(ScriptError(code: -1, message: "Could not compile script"))
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? -1
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            return .failure(ScriptError(code: code, message: message))
        }
        return .success(result)
    }
}
