import Foundation
import Testing

@Suite("Arm64OnlyBuildConfiguration")
struct Arm64OnlyBuildConfigurationTests {
    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test
    func xcframeworkLibraryIsArm64Only() throws {
        let library = repoRoot
            .appendingPathComponent("ABridgeCore/abridge_core.xcframework/macos-arm64/libabridge_core.a")
        #expect(FileManager.default.fileExists(atPath: library.path))

        let output = try runCommand(executable: "/usr/bin/lipo", arguments: ["-info", library.path])
        #expect(output.contains("architecture: arm64") || output.contains("are: arm64"))
        #expect(!output.contains("x86_64"))
        #expect(!output.contains("are: x86_64"))
    }

    @Test
    func projectYAMLDeclaresArm64OnlyAndMacOS26() throws {
        let projectYAML = repoRoot.appendingPathComponent("project.yml")
        let contents = try String(contentsOf: projectYAML, encoding: .utf8)
        #expect(contents.contains("ARCHS: arm64"))
        #expect(contents.contains("EXCLUDED_ARCHS: x86_64"))
        #expect(contents.contains("MACOSX_DEPLOYMENT_TARGET: \"26.0\""))
        #expect(!contents.contains("x86_64-apple-darwin"))
    }

    @Test
    func rustBuildScriptTargetsAArch64Only() throws {
        let script = repoRoot.appendingPathComponent("rust/build-macos.sh")
        let contents = try String(contentsOf: script, encoding: .utf8)
        #expect(contents.contains("aarch64-apple-darwin"))
        #expect(!contents.contains("x86_64-apple-darwin"))
        #expect(!contents.contains("lipo"))
    }

    private func runCommand(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(bytes: data, encoding: .utf8) ?? ""
        let command = "\(executable) \(arguments.joined(separator: " "))"
        #expect(process.terminationStatus == 0, "command failed: \(command) — \(output)")
        return output
    }
}
