import Darwin
import Foundation

enum VisionProviderError: Error, Equatable {
    case serializationFailed
    case visionError(String)
    case invalidArguments(String)
}

enum VisionImageLimits {
    /// Same cap as Rust `rendition::MAX_RESOURCE_BYTES`.
    static let maxFileBytes = 20 * 1024 * 1024
}

enum LiveVisionEnvironment {
    static let sharedProvider = VisionProvider()
}

/// Adapter layer; pure schema validation is Rust (`arg_validation`).
struct VisionProvider {
    let store: any VisionStoreing

    init(store: any VisionStoreing = LiveVisionStore()) {
        self.store = store
    }

    func parseJSONObject(from data: Data) throws -> [String: Any] {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw VisionProviderError.invalidArguments("Arguments must be valid JSON object")
        }

        guard let dictionary = object as? [String: Any] else {
            throw VisionProviderError.invalidArguments("Arguments must be a JSON object")
        }

        return dictionary
    }

    func providerErrorResponse(from error: VisionProviderError) -> ProviderResponse {
        switch error {
        case let .invalidArguments(message):
            errorResponse(code: "invalid_arguments", message: message)
        case .serializationFailed:
            errorResponse(code: "vision_error", message: "Failed to serialize Vision response")
        case let .visionError(message):
            errorResponse(code: "vision_error", message: message)
        }
    }

    /// Exactly one of `image_data` (base64) or `image_path` (absolute path on this Mac).
    /// Rust `arg_validation` enforces that before dispatch; this also covers direct provider calls.
    func imageDataArgument(in dictionary: [String: Any]) throws -> Data {
        let encodedImage = dictionary["image_data"] as? String
        let imagePath = dictionary["image_path"] as? String
        switch (encodedImage, imagePath) {
        case let (data?, nil):
            guard let decoded = Data(base64Encoded: data) else {
                throw VisionProviderError.invalidArguments("image_data must be valid base64")
            }
            return decoded
        case let (nil, path?):
            return try imageData(atAbsolutePath: path)
        default:
            throw VisionProviderError.invalidArguments("Provide exactly one of image_data or image_path.")
        }
    }

    private func imageData(atAbsolutePath path: String) throws -> Data {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else {
            throw VisionProviderError.invalidArguments("image_path must be an absolute path")
        }
        return try readRegularFile(atAbsolutePath: trimmed, limit: VisionImageLimits.maxFileBytes)
    }

    func errorResponse(code: String, message: String) -> ProviderResponse {
        let payload: [String: String] = ["code": code, "message": message]
        let errorJson = (try? VisionSerialization.jsonString(from: payload)) ?? #"{"code":"provider_error"}"#
        return ProviderResponse(ok: false, payloadJson: "{}", errorJson: errorJson)
    }
}

/// Opens `path` once and follows a symlink when the final target is a regular file.
/// FIFOs and devices are rejected from that file descriptor before any blocking read.
/// At most `limit + 1` bytes are read.
private func readRegularFile(atAbsolutePath path: String, limit: Int) throws -> Data {
    let fd = path.withCString { open($0, O_RDONLY | O_NONBLOCK | O_CLOEXEC) }
    guard fd >= 0 else {
        let reason = errno == ENOENT
            ? "no file at image_path on this server Mac"
            : "image_path could not be opened on this server Mac (\(String(cString: strerror(errno))))"
        throw VisionProviderError.invalidArguments(
            "\(reason). image_path is resolved on the server Mac, not the caller; send the bytes as image_data instead"
        )
    }
    defer { close(fd) }

    var info = stat()
    guard fstat(fd, &info) == 0 else {
        throw VisionProviderError.invalidArguments("image_path could not be read")
    }
    guard info.st_mode & S_IFMT == S_IFREG else {
        throw VisionProviderError.invalidArguments("image_path is not a file")
    }
    if info.st_size > Int64(limit) {
        throw VisionProviderError.invalidArguments("image_path is larger than 20 MiB")
    }

    var data = Data()
    let cap = limit + 1
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while data.count < cap {
        let count = buffer.withUnsafeMutableBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return Darwin.read(fd, base, min(raw.count, cap - data.count))
        }
        if count == 0 {
            break
        }
        if count < 0 {
            if errno == EINTR {
                continue
            }
            throw VisionProviderError.invalidArguments("image_path could not be read")
        }
        data.append(contentsOf: buffer.prefix(count))
    }
    guard data.count <= limit else {
        throw VisionProviderError.invalidArguments("image_path is larger than 20 MiB")
    }
    return data
}
