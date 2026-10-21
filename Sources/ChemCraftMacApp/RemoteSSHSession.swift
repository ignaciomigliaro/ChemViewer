import AppKit
import Foundation
import Darwin

/// One SSH process and one remote Python helper, with serialized newline-framed RPC.
/// Closing this channel never cancels a detached ChemRefine calculation.
final class RemoteSSHSession: @unchecked Sendable {
    let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffered = Data()
    private let folder: URL
    private let errorFile: URL
    private let errorHandle: FileHandle
    private(set) var requests = 0

    init(arguments: [String], executable: URL = URL(fileURLWithPath: "/usr/bin/ssh")) throws {
        guard arguments.first == executable.path else { throw RemoteError.message("Invalid SSH command.") }
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("chemviewer-channel-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        errorFile = folder.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: errorFile.path, contents: nil)
        errorHandle = try FileHandle(forWritingTo: errorFile)
        process.executableURL = URL(fileURLWithPath: arguments[0]); process.arguments = Array(arguments.dropFirst())
        process.standardInput = input; process.standardOutput = output; process.standardError = errorHandle
        try process.run()
    }
    func close() {
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [process] in
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }
    deinit { close(); try? errorHandle.close(); try? FileManager.default.removeItem(at: folder) }

    func exchange(_ payload: [String: Any]) async throws -> [String: Any] {
        let request = try JSONSerialization.data(withJSONObject: payload) + Data([10])
        let start = Date()
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let deadline = DispatchWorkItem { [self] in close() }
                DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: deadline)
                defer { deadline.cancel() }
                do {
                    try input.fileHandleForWriting.write(contentsOf: request)
                    while true {
                        if let end = buffered.firstIndex(of: 10) {
                            let line = Data(buffered[..<end]); buffered.removeSubrange(...end)
                            let prefix = Data("CHEMVIEWER_JSON:".utf8)
                            guard line.starts(with: prefix) else { continue }
                            guard var response = try JSONSerialization.jsonObject(with: line.dropFirst(prefix.count)) as? [String: Any] else { throw RemoteError.message("Invalid SSH response.") }
                            requests += 1
                            response["transport"] = ["ssh_pid": Int(process.processIdentifier), "requests": requests, "reused": requests > 1, "milliseconds": Int(Date().timeIntervalSince(start) * 1000)]
                            continuation.resume(returning: response); return
                        }
                        // POSIX read returns available pipe bytes immediately; FileHandle's
                        // length-oriented read can wait for a full chunk on a live channel.
                        var bytes = [UInt8](repeating: 0, count: 65_536)
                        let count = Darwin.read(output.fileHandleForReading.fileDescriptor, &bytes, bytes.count)
                        if count < 0 && errno == EINTR { continue }
                        guard count > 0 else {
                            var detail = ""
                            if let reader = try? FileHandle(forReadingFrom: errorFile) {
                                let end = (try? reader.seekToEnd()) ?? 0
                                try? reader.seek(toOffset: end > 6000 ? end - 6000 : 0)
                                detail = String(data: (try? reader.readToEnd()) ?? Data(), encoding: .utf8) ?? ""
                                try? reader.close()
                            }
                            throw RemoteError.message("SSH channel closed or timed out. \(detail) Reconnect or authenticate in Terminal if needed. A submitted calculation may still be running; check its status before retrying Run.")
                        }
                        buffered.append(contentsOf: bytes[..<count])
                        guard buffered.count <= 150_000_000 else { throw RemoteError.message("SSH response exceeds the supported file limit.") }
                    }
                } catch { close(); continuation.resume(throwing: error) }
            }
        }
    }
}
