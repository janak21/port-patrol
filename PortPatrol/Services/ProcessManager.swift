import Foundation
import Darwin

enum ProcessManager {

    enum KillResult {
        case success
        case failure(String)
    }

    private static func runKill(signal: Int32, pid: Int) -> KillResult {
        if kill(pid_t(pid), signal) == 0 {
            return .success
        } else {
            let error = String(cString: strerror(errno))
            return .failure(error)
        }
    }

    /// Sends SIGTERM (graceful shutdown) to the given PID
    static func terminate(pid: Int) -> KillResult {
        return runKill(signal: SIGTERM, pid: pid)
    }

    /// Sends SIGKILL (force kill) to the given PID
    static func forceKill(pid: Int) -> KillResult {
        return runKill(signal: SIGKILL, pid: pid)
    }
}
