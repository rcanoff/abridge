import Foundation

/// Task executor backed by one long-lived thread, so Vision work runs off the main thread on a
/// thread with a known stack size.
final class VisionWorkerExecutor: TaskExecutor, @unchecked Sendable {
    private let condition = NSCondition()
    private var jobs: [UnownedJob] = []

    init(stackSize: Int) {
        let thread = Thread { [unowned self] in
            drain()
        }
        thread.name = "ABridge Vision"
        thread.stackSize = stackSize
        thread.start()
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        condition.lock()
        jobs.append(job)
        condition.signal()
        condition.unlock()
    }

    private func drain() {
        while true {
            condition.lock()
            while jobs.isEmpty {
                condition.wait()
            }
            let job = jobs.removeFirst()
            condition.unlock()
            job.runSynchronously(on: asUnownedTaskExecutor())
        }
    }
}
