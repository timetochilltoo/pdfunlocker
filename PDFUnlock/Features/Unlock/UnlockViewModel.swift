import Foundation
import Observation

/// Drives the unlock queue. Owns the runner `Task` and the inspector
/// task so cancellation is clean across the whole queue.
@Observable
@MainActor
public final class UnlockViewModel {

    private let inspector: PDFInspector
    private let unlocker: PDFUnlocker

    private var runningTask: Task<Void, Never>?
    private var inspectionTasks: [UUID: Task<Void, Never>] = [:]

    /// Bumped each time a successful run finishes — views can observe
    /// it to refresh preflight counts without depending on the queue.
    public var runFinishedToken: Int = 0

    public init(
        inspector: PDFInspector = PDFInspector(),
        unlocker: PDFUnlocker = PDFUnlocker()
    ) {
        self.inspector = inspector
        self.unlocker = unlocker
    }

    // MARK: - Inspection

    /// Inspect every queued job (lightweight; runs on a background
    /// detached task per file).
    public func inspectAll(_ jobs: [UnlockJob]) {
        for job in jobs where job.inspection == nil {
            startInspection(for: job)
        }
    }

    public func inspect(_ job: UnlockJob) {
        startInspection(for: job)
    }

    private func startInspection(for job: UnlockJob) {
        inspectionTasks[job.id]?.cancel()
        job.status = .inspecting
        let task = Task.detached(priority: .utility) { [inspector] in
            let result = inspector.inspect(job.inputURL)
            await MainActor.run {
                job.inspection = result
                if job.status == .inspecting {
                    job.status = Self.initialStatus(for: result)
                }
            }
        }
        inspectionTasks[job.id] = task
    }

    private static func initialStatus(for inspection: PDFInspection) -> UnlockStatus {
        if inspection.isCorrupt { return .failed }
        switch inspection.encryption {
        case .none:           return .skipped
        case .ownerOnly:      return .ready
        case .userPassword:   return .needsPassword
        case .certificate,
             .unsupported:    return .failed
        }
    }

    // MARK: - Run queue

    /// Run all `jobs`. Limits concurrency from `settings.concurrency`.
    public func runAll(_ jobs: [UnlockJob], settings: AppSettings) {
        guard runningTask == nil else { return }
        let eligible = jobs.filter {
            switch $0.status {
            case .ready, .needsPassword, .failed: return true
            default: return false
            }
        }
        guard !eligible.isEmpty else { return }

        let options = PDFUnlocker.Options(
            overwriteExisting: settings.collisionBehavior == .overwrite,
            preserveMetadata: true,
            useQPDFFallback: true
        )

        runningTask = Task { [unlocker, weak self] in
            await withTaskGroup(of: Void.self) { group in
                var inFlight = 0
                let maxConcurrency = max(1, min(settings.concurrency, eligible.count))
                var iterator = eligible.makeIterator()

                func startNext() {
                    guard let job = iterator.next() else { return }
                    inFlight += 1
                    group.addTask { [unlocker] in
                        await Self.runOne(job: job, unlocker: unlocker, options: options)
                    }
                }

                for _ in 0..<maxConcurrency { startNext() }

                while await group.next() != nil {
                    inFlight -= 1
                    if Task.isCancelled { break }
                    startNext()
                }
            }
            await MainActor.run {
                self?.runningTask = nil
                self?.runFinishedToken &+= 1
            }
        }
    }

    /// Run a single job (used by retry).
    public func run(_ job: UnlockJob, settings: AppSettings) {
        let options = PDFUnlocker.Options(
            overwriteExisting: settings.collisionBehavior == .overwrite,
            preserveMetadata: true,
            useQPDFFallback: true
        )
        Task { [unlocker] in
            await Self.runOne(job: job, unlocker: unlocker, options: options)
        }
    }

    /// Cancel any in-flight runs and inspections.
    public func cancelAll() {
        runningTask?.cancel()
        runningTask = nil
        for task in inspectionTasks.values { task.cancel() }
        inspectionTasks.removeAll()
    }

    /// Apply a session-wide password to every job that needs one.
    public func applySharedPassword(_ password: String, to jobs: [UnlockJob]) {
        for job in jobs where job.inspection?.encryption == .userPassword {
            job.password = password
            if job.status == .needsPassword {
                job.status = .ready
            }
        }
    }

    public func clearSharedPassword(from jobs: [UnlockJob]) {
        for job in jobs where job.inspection?.encryption == .userPassword {
            job.password = ""
            job.status = .needsPassword
        }
    }

    /// Remove a job from the queue.
    public func remove(_ job: UnlockJob, from jobs: inout [UnlockJob]) {
        inspectionTasks[job.id]?.cancel()
        inspectionTasks[job.id] = nil
        jobs.removeAll { $0.id == job.id }
    }

    // MARK: - Single-job runner

    private static func runOne(
        job: UnlockJob,
        unlocker: PDFUnlocker,
        options: PDFUnlocker.Options
    ) async {
        await MainActor.run {
            job.status = .running
            job.progress = 0.1
            job.errorMessage = nil
        }

        let naming = FileNaming(suffix: job.inspection.flatMap { _ in "-unlocked" } ?? "-unlocked")

        // Build candidate output URL using settings collision behavior.
        let candidate = naming.defaultOutput(for: job.inputURL, target: .unlock)
        let resolved: URL
        do {
            resolved = try naming.resolveCollision(
                candidate: candidate,
                behavior: options.overwriteExisting ? .overwrite : .keepBoth
            )
        } catch {
            await MainActor.run {
                job.status = .failed
                job.errorMessage = error.localizedDescription
            }
            return
        }

        do {
            let result = try await unlocker.unlock(
                input: job.inputURL,
                output: resolved,
                password: job.password.isEmpty ? nil : job.password,
                options: options
            )
            await MainActor.run {
                job.outputURL = result.outputURL
                job.progress = 1.0
                job.status = .succeeded
                job.password = ""  // clear from memory
            }
        } catch is CancellationError {
            await MainActor.run {
                job.status = .cancelled
                job.password = ""
            }
        } catch let error as UnlockError {
            await MainActor.run {
                job.status = .failed
                job.errorMessage = error.errorDescription
                job.password = ""
            }
        } catch {
            await MainActor.run {
                job.status = .failed
                job.errorMessage = error.localizedDescription
                job.password = ""
            }
        }
    }
}