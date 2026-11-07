import XCTest
@testable import ApexSSH
import ApexCore

/// Regression: the local login shell must own a controlling terminal, otherwise the
/// PTY line discipline has no foreground process group and Ctrl+C (SIGINT via ISIG)
/// is silently swallowed — typed input could never be cancelled.
final class LocalTerminalCtrlCTest: XCTestCase {

    /// Spawns `sleep 30` in the app's local shell, sends 0x03 (Ctrl+C) and asserts
    /// the foreground child is actually interrupted.
    func testCtrlCInterruptsForegroundCommand() async throws {
        let session = LocalTerminalSession()
        try await session.connect()
        defer {
            let closing = session
            Task { await closing.disconnect() }
        }

        let shellPid = session.shellProcessIdentifier
        XCTAssertGreaterThan(shellPid, 0, "local shell should be running")

        func shellHasSleepChild() -> Bool {
            let pgrep = Process()
            pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            pgrep.arguments = ["-P", "\(shellPid)", "-x", "sleep"]
            let pipe = Pipe()
            pgrep.standardOutput = pipe
            do { try pgrep.run() } catch { return false }
            pgrep.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let ids = String(data: data, encoding: .utf8) ?? ""
            return !ids.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        // Wait for the prompt, then start a foreground sleep.
        try await Task.sleep(nanoseconds: 800_000_000)
        session.sendInputSync(Data("sleep 30\n".utf8))

        var sleepStarted = false
        for _ in 0..<20 where !sleepStarted {
            if shellHasSleepChild() { sleepStarted = true } else {
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        XCTAssertTrue(sleepStarted, "sleep should be running as a child of the shell")

        // Ctrl+C
        session.sendInputSync(Data([0x03]))

        var interrupted = false
        for _ in 0..<25 where !interrupted {
            if !shellHasSleepChild() { interrupted = true } else {
                try await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        XCTAssertTrue(interrupted, "Ctrl+C must SIGINT the foreground sleep (controlling terminal via login_tty)")
    }
}
