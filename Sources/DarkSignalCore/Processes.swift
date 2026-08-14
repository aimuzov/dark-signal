import Darwin
import Foundation

public enum Processes {
    /// `proc_name` writes at most this many characters. Measured, not guessed: with a
    /// buffer of MAXCOMLEN + 1 it writes nothing at all and reports zero, and the
    /// longest name it ever returns is 31 characters — anything longer comes back cut
    /// ("com.apple.WebKit.WebContent.Enh" for …EnhancedSecurity).
    static let nameLimit = 2 * Int(MAXCOMLEN) - 1
    static let nameBufferSize = 2 * Int(MAXCOMLEN) + 1

    /// Every running process with this executable name.
    ///
    /// Asked of the kernel through libproc rather than by shelling out to pgrep: the
    /// agent runs under launchd, where PATH is short, and a missing pgrep would fail
    /// silently on exactly the machines that are hardest to debug.
    public static func pids(named name: String) -> [pid_t] {
        // Both the probe and the real call answer in *pids*, not in bytes, despite what
        // the header's "buffersize" wording suggests. Dividing the result by
        // sizeof(pid_t) silently drops three quarters of the process table.
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else {
            return []
        }

        // Room to spare: processes keep starting between the probe and the call
        var buffer = [pid_t](repeating: 0, count: Int(capacity) + 128)
        let returned = proc_listallpids(&buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        guard returned > 0 else {
            return []
        }

        let count = min(Int(returned), buffer.count)
        let own = getpid()

        return buffer.prefix(count).filter { pid in
            // Signalling yourself is never what the caller meant
            guard pid > 0, pid != own, let actual = self.name(of: pid) else {
                return false
            }
            return matches(actual, name)
        }
    }

    public static func matches(_ actual: String, _ wanted: String) -> Bool {
        if actual == wanted {
            return true
        }
        // A name that came back at the limit may have been cut, so a longer wanted
        // name still counts as a match on that prefix
        return actual.count >= nameLimit && wanted.hasPrefix(actual)
    }

    public static func name(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: nameBufferSize)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else {
            return nil
        }

        return String(cString: buffer)
    }

    /// Returns the pids the signal actually reached.
    @discardableResult
    public static func send(_ signal: Int32, toProcessesNamed name: String) -> [pid_t] {
        pids(named: name).filter { kill($0, signal) == 0 }
    }
}
