import Foundation

enum StartupTrace {
    private static var logURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("startup-trace.log", isDirectory: false)
    }

    static func reset() {
        guard let logURL else { return }
        try? FileManager.default.removeItem(at: logURL)
    }

    static func mark(_ message: String) {
        guard let logURL else { return }

        let threadLabel = Thread.isMainThread ? "main" : "background"
        let line = String(format: "%.3f [%@] %@\n", Date().timeIntervalSince1970, threadLabel, message)
        let data = Data(line.utf8)

        if FileManager.default.fileExists(atPath: logURL.path) == false {
            FileManager.default.createFile(atPath: logURL.path, contents: data)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }
}
