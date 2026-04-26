import AppKit
import Darwin
import Foundation

struct Manifest: Decodable {
    let version: Int
    let logDir: String?
    let selfTest: SelfTest?
    let services: [CommandSpec]
    let jobs: [CommandSpec]
}

struct SelfTest: Decodable {
    let directWritePath: String
    let childWritePath: String
    let hardlinkSourcePath: String
    let hardlinkTargetPath: String
}

struct CommandSpec: Decodable {
    let name: String
    let argv: [String]
    let env: [String: String]?
    let cwd: String?
    let stdout: String?
    let stderr: String?
}

enum SupervisorError: Error, CustomStringConvertible {
    case missingManifest
    case invalidCommand(String)
    case commandFailed(String, Int32)
    case hardlinkMismatch(String, String)
    case networkVolumeUnavailable(String)

    var description: String {
        switch self {
        case .missingManifest:
            return "usage: NixflixSupervisor <manifest.json>"
        case .invalidCommand(let name):
            return "command '\(name)' has empty argv"
        case .commandFailed(let name, let status):
            return "command '\(name)' failed with exit status \(status)"
        case .hardlinkMismatch(let source, let target):
            return "hardlink self-test failed: \(source) and \(target) are not the same inode with link count >= 2"
        case .networkVolumeUnavailable(let path):
            return "network volume unavailable for self-test path: \(path)"
        }
    }
}

final class Logger {
    private let handle: FileHandle?

    init(logDir: String?) {
        guard let logDir else {
            self.handle = nil
            return
        }

        try? FileManager.default.createDirectory(
            atPath: logDir,
            withIntermediateDirectories: true
        )
        let path = "\(logDir)/supervisor.log"
        FileManager.default.createFile(atPath: path, contents: nil)
        self.handle = FileHandle(forWritingAtPath: path)
        _ = try? self.handle?.seekToEnd()
    }

    func info(_ message: String) {
        let line = "[\(Date())] \(message)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
        try? handle?.write(contentsOf: Data(line.utf8))
    }
}

func mkdirForFile(_ path: String) throws {
    let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
}

func writeText(_ text: String, to path: String) throws {
    try mkdirForFile(path)
    let fd = open(path, O_CREAT | O_WRONLY | O_TRUNC, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
    if fd == -1 {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    defer { close(fd) }

    try text.utf8CString.withUnsafeBufferPointer { buffer in
        let byteCount = buffer.count - 1
        let written = Darwin.write(fd, buffer.baseAddress, byteCount)
        if written != byteCount {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}

func removeIfExists(_ path: String) throws {
    if FileManager.default.fileExists(atPath: path) {
        try FileManager.default.removeItem(atPath: path)
    }
}

func statInfo(_ path: String) throws -> stat {
    var info = stat()
    if stat(path, &info) != 0 {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return info
}

func fileSystemType(for path: String) throws -> String {
    var info = statfs()
    if statfs(path, &info) != 0 {
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    var fileSystemName = info.f_fstypename
    let fileSystemNameSize = MemoryLayout.size(ofValue: fileSystemName)
    return withUnsafePointer(to: &fileSystemName) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: fileSystemNameSize) {
            String(cString: $0)
        }
    }
}

func waitForNetworkVolume(containing path: String, logger: Logger) throws {
    let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path
    let deadline = Date().addingTimeInterval(180)

    while Date() < deadline {
        if FileManager.default.fileExists(atPath: directory),
           (try? fileSystemType(for: directory)) == "nfs" {
            return
        }

        logger.info("waiting for NAS mount before self-test: \(directory)")
        Thread.sleep(forTimeInterval: 5)
    }

    throw SupervisorError.networkVolumeUnavailable(directory)
}

@discardableResult
func run(_ spec: CommandSpec, logger: Logger, wait: Bool) throws -> Process {
    guard let executable = spec.argv.first else {
        throw SupervisorError.invalidCommand(spec.name)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = Array(spec.argv.dropFirst())

    var environment = ProcessInfo.processInfo.environment
    for (key, value) in spec.env ?? [:] {
        environment[key] = value
    }
    process.environment = environment

    if let cwd = spec.cwd {
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
    }

    if let stdout = spec.stdout {
        try mkdirForFile(stdout)
        FileManager.default.createFile(atPath: stdout, contents: nil)
        process.standardOutput = FileHandle(forWritingAtPath: stdout)
    }

    if let stderr = spec.stderr {
        try mkdirForFile(stderr)
        FileManager.default.createFile(atPath: stderr, contents: nil)
        process.standardError = FileHandle(forWritingAtPath: stderr)
    }

    logger.info("starting \(spec.name): \(spec.argv.joined(separator: " "))")
    try process.run()

    if wait {
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw SupervisorError.commandFailed(spec.name, process.terminationStatus)
        }
        logger.info("finished \(spec.name)")
    }

    return process
}

func runSelfTest(_ selfTest: SelfTest, logger: Logger) throws {
    try waitForNetworkVolume(containing: selfTest.directWritePath, logger: logger)
    logger.info("running NAS write and hardlink self-test")
    try writeText("nixflix supervisor direct write\n", to: selfTest.directWritePath)

    try run(
        CommandSpec(
            name: "child-write-probe",
            argv: ["/usr/bin/touch", selfTest.childWritePath],
            env: nil,
            cwd: nil,
            stdout: nil,
            stderr: nil
        ),
        logger: logger,
        wait: true
    )

    try removeIfExists(selfTest.hardlinkSourcePath)
    try removeIfExists(selfTest.hardlinkTargetPath)
    try writeText("nixflix supervisor hardlink probe\n", to: selfTest.hardlinkSourcePath)
    try FileManager.default.linkItem(atPath: selfTest.hardlinkSourcePath, toPath: selfTest.hardlinkTargetPath)

    let source = try statInfo(selfTest.hardlinkSourcePath)
    let target = try statInfo(selfTest.hardlinkTargetPath)
    guard source.st_dev == target.st_dev, source.st_ino == target.st_ino, source.st_nlink >= 2 else {
        throw SupervisorError.hardlinkMismatch(selfTest.hardlinkSourcePath, selfTest.hardlinkTargetPath)
    }
    logger.info("self-test passed: device=\(source.st_dev) inode=\(source.st_ino) links=\(source.st_nlink)")
}

func stop(_ processes: [Process], logger: Logger) {
    for process in processes where process.isRunning {
        logger.info("stopping \(process.executableURL?.lastPathComponent ?? "service")")
        process.terminate()
    }

    for process in processes where process.isRunning {
        process.waitUntilExit()
    }
}

func servicesNeedingRestart(after jobs: [CommandSpec], services: [(spec: CommandSpec, process: Process)]) -> [Process] {
    let serviceNames = Set(services.map(\.spec.name))
    let jobPrefixes = jobs.compactMap { job -> String? in
        guard job.name.hasSuffix("-config") else {
            return nil
        }

        return String(job.name.dropLast("-config".count))
    }

    return jobPrefixes
        .filter { serviceNames.contains($0) }
        .compactMap { name in services.first { $0.spec.name == name }?.process }
}

func defaultManifestPath() -> String {
    "\(NSHomeDirectory())/Library/Application Support/nixflix/supervisor-manifest.json"
}

func runSupervisor() throws {
    let manifestPath = CommandLine.arguments.dropFirst().first
        ?? ProcessInfo.processInfo.environment["NIXFLIX_SUPERVISOR_MANIFEST"]
        ?? defaultManifestPath()

    let data = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
    let manifest = try JSONDecoder().decode(Manifest.self, from: data)
    let logger = Logger(logDir: manifest.logDir)

    guard manifest.version == 1 else {
        throw SupervisorError.commandFailed("manifest-version", Int32(manifest.version))
    }

    if let selfTest = manifest.selfTest {
        try runSelfTest(selfTest, logger: logger)
    }

    var services: [(spec: CommandSpec, process: Process)] = []

    do {
        for service in manifest.services {
            services.append((spec: service, process: try run(service, logger: logger, wait: false)))
        }

        for job in manifest.jobs {
            try run(job, logger: logger, wait: true)
        }

        let restartProcesses = servicesNeedingRestart(after: manifest.jobs, services: services)
        if !restartProcesses.isEmpty {
            logger.info("restarting \(restartProcesses.count) service process(es) after convergence jobs")
            stop(restartProcesses, logger: logger)
            services = services.filter { $0.process.isRunning }

            for service in manifest.services where !services.contains(where: { $0.spec.name == service.name }) {
                services.append((spec: service, process: try run(service, logger: logger, wait: false)))
            }
        }
    } catch {
        stop(services.map(\.process), logger: logger)
        throw error
    }

    logger.info("supervising \(services.count) service process(es)")
    while true {
        services.removeAll { service in
            guard !service.process.isRunning else {
                return false
            }

            if service.process.terminationStatus == 0 {
                logger.info("\(service.spec.name) starter exited cleanly")
                return true
            }

            return false
        }

        for service in services where !service.process.isRunning {
            throw SupervisorError.commandFailed(service.spec.name, service.process.terminationStatus)
        }
        Thread.sleep(forTimeInterval: 5)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try runSupervisor()
            } catch {
                FileHandle.standardError.write(Data("NixflixSupervisor: \(error)\n".utf8))
                DispatchQueue.main.async {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
