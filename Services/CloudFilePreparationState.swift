import Foundation

@MainActor
@Observable
final class CloudFilePreparationState {
    enum Phase {
        case downloading
        case startingPlayback
    }

    private(set) var isActive = false
    private(set) var fileName = ""
    private(set) var phase: Phase = .downloading
    /// `nil` = 進捗不明（スピナー）、0...1 = 確定進捗
    private(set) var progress: Double?

    var progressPercent: Int? {
        guard let progress else { return nil }
        return min(100, max(0, Int(progress * 100)))
    }

    func begin(fileName: String) {
        self.fileName = fileName
        phase = .downloading
        progress = nil
        isActive = true
    }

    func setPhase(_ phase: Phase) {
        self.phase = phase
    }

    func updateProgress(_ value: Double?) {
        progress = value
    }

    func end() {
        isActive = false
        fileName = ""
        phase = .downloading
        progress = nil
    }
}
