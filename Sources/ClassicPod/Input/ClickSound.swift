import AVFoundation

@MainActor final class ClickSound {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let buffer: AVAudioPCMBuffer
    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 600)!
        buffer.frameLength = 600
        for index in 0..<600 {
            let time = Double(index) / 44100
            buffer.floatChannelData![0][index] = Float(sin(time * 2 * .pi * 2800) * exp(-time * 650) * 0.22)
        }
        engine.attach(player); engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }
    func tick() {
        if !engine.isRunning { do { try engine.start() } catch { return } }
        if !player.isPlaying { player.play() }
        player.scheduleBuffer(buffer)
    }
    func stop() { player.stop(); engine.stop() }
}
