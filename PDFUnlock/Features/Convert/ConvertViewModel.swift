import Foundation
import Observation
import PDFKit

/// Drives the convert queue. Mirrors `UnlockViewModel` shape but talks
/// to `PDFConverter` instead of `PDFUnlocker`.
@Observable
@MainActor
public final class ConvertViewModel {

    private let converter: PDFConverter

    private var runningTask: Task<Void, Never>?
    private var inspectionTasks: [UUID: Task<Void, Never>] = [:]

    /// Bumped each time a successful run finishes.
    public var runFinishedToken: Int = 0

    public init(converter: PDFConverter = PDFConverter()) {
        self.converter = converter
    }

    // MARK: - Inspection

    public func inspectAll(_ jobs: [ConvertJob]) {
        for job in jobs where job.status == .queued {
            startInspection(for: job)
        }
    }

    private func startInspection(for job: ConvertJob) {
        inspectionTasks[job.id]?.cancel()
        job.status = .inspecting
        let task = Task.detached(priority: .utility) {
            let pageCount = PDFDocument(url: job.inputURL)?.pageCount ?? 0
            await MainActor.run {
                _ = pageCount
                job.status = .ready
            }
        }
        inspectionTasks[job.id] = task
    }

    // MARK: - Run queue

    public func runAll(_ jobs: [ConvertJob], settings: AppSettings) {
        guard runningTask == nil else { return }
        let eligible = jobs.filter {
            switch $0.status {
            case .ready, .failed: return true
            default: return false
            }
        }
        guard !eligible.isEmpty else { return }

        let options = PDFConverter.Options(
            formats: settings.defaultMarkdown ? [.txt, .png, .md] : [.txt, .png],
            pageRange: nil,
            pngDPI: settings.defaultPNGDPI
        )

        runningTask = Task { [converter, weak self] in
            await withTaskGroup(of: Void.self) { group in
                var inFlight = 0
                let maxConcurrency = max(1, min(settings.concurrency, eligible.count))
                var iterator = eligible.makeIterator()

                func startNext() {
                    guard let job = iterator.next() else { return }
                    inFlight += 1
                    group.addTask { [converter] in
                        await Self.runOne(job: job, converter: converter, options: options)
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
    public func run(_ job: ConvertJob, settings: AppSettings) {
        let options = PDFConverter.Options(
            formats: settings.defaultMarkdown ? [.txt, .png, .md] : [.txt, .png],
            pageRange: job.pageRange,
            pngDPI: settings.defaultPNGDPI
        )
        Task { [converter] in
            await Self.runOne(job: job, converter: converter, options: options)
        }
    }

    public func cancelAll() {
        runningTask?.cancel()
        runningTask = nil
        for task in inspectionTasks.values { task.cancel() }
        inspectionTasks.removeAll()
    }

    public func remove(_ job: ConvertJob, from jobs: inout [ConvertJob]) {
        inspectionTasks[job.id]?.cancel()
        inspectionTasks[job.id] = nil
        jobs.removeAll { $0.id == job.id }
    }

    /// Per-job runner.
    private static func runOne(
        job: ConvertJob,
        converter: PDFConverter,
        options: PDFConverter.Options
    ) async {
        await MainActor.run {
            job.status = .running
            job.progress = 0.1
            job.errorMessage = nil
        }

        let outputDir = job.outputDirectory
        do {
            let result = try await converter.convert(
                input: job.inputURL,
                outputDirectory: outputDir,
                options: options
            )
            await MainActor.run {
                job.outputs[.txt] = result.output.txt
                job.outputs[.md] = result.output.md
                job.outputs[.png] = result.output.pngFolder
                job.progress = 1.0
                if result.hadNoTextLayer
                    && (result.output.txt == nil || result.output.md == nil) {
                    job.status = .partialSuccess
                    job.errorMessage = "No text layer in PDF — TXT/MD may be empty."
                } else {
                    job.status = .succeeded
                }
            }
        } catch is CancellationError {
            await MainActor.run { job.status = .cancelled }
        } catch let error as ConvertError {
            await MainActor.run {
                job.status = .failed
                job.errorMessage = error.errorDescription
            }
        } catch {
            await MainActor.run {
                job.status = .failed
                job.errorMessage = error.localizedDescription
            }
        }
    }
}