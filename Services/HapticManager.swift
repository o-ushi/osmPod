import UIKit
import AVFoundation

@MainActor
final class HapticManager {
    static let shared = HapticManager()

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioBuffer: AVAudioPCMBuffer?
    private var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private let clickSoundID: SystemSoundID = 1104

    private init() {
        for style in [UIImpactFeedbackGenerator.FeedbackStyle.light, .medium, .heavy] {
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            impactGenerators[style] = generator
        }
        setupAudioEngine()
    }

    private func setupAudioEngine() {
        audioEngine.attach(playerNode)
        let format = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        audioBuffer = createClickSoundBuffer(format: format)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
        do { try audioEngine.start() } catch {}
    }

    private func createClickSoundBuffer(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let channelCount = Int(format.channelCount)
        let frameCount = UInt32(sampleRate * 0.02)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData else { return nil }
        buffer.frameLength = frameCount

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            for i in 0..<Int(frameCount) {
                let progress = Double(i) / Double(frameCount)
                let envelope = pow(1.0 - progress, 2.0)
                samples[i] = Float(sin(2.0 * .pi * 1200.0 * Double(i) / sampleRate) * envelope)
            }
        }
        return buffer
    }

    func provideFeedback() {
        if AppSettings.enableHapticFeedback {
            playHaptic(intensity: AppSettings.hapticIntensity)
        }
        if AppSettings.enableSoundFeedback {
            playSound(volume: AppSettings.soundVolume)
        }
    }

    func previewSound(volume: Double) {
        playSound(volume: volume)
    }

    private func playHaptic(intensity: HapticIntensity) {
        guard let generator = impactGenerators[intensity.impactStyle] else { return }
        generator.impactOccurred()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.1))
            generator.prepare()
        }
    }

    private func playSound(volume: Double) {
        guard volume > 0 else { return }
        // 再生中は AVAudioEngine を起動しない（AVPlayer のセッションと競合してノイズの原因になる）。
        if PodcastPlaybackActivity.isActive {
            AudioServicesPlaySystemSound(clickSoundID)
            return
        }
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
                Thread.sleep(forTimeInterval: 0.01)
            } catch {
                AudioServicesPlaySystemSound(clickSoundID)
                return
            }
        }
        guard let buffer = audioBuffer else {
            AudioServicesPlaySystemSound(clickSoundID)
            return
        }
        playerNode.volume = Float(volume)
        audioEngine.mainMixerNode.outputVolume = 1.0
        playerNode.stop()
        playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        playerNode.play()
    }
}
