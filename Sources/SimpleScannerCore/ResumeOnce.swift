import Foundation

/// Lets a racing lookup and its timeout agree on who resumes the continuation.
final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false

    func fire(_ body: () -> Void) {
        lock.lock()
        let shouldRun = !fired
        fired = true
        lock.unlock()
        if shouldRun { body() }
    }
}
