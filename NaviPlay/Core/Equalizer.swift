import Foundation
import AVFoundation
import AudioToolbox
import MediaToolbox

enum EqualizerMode: String, CaseIterable, Codable, Identifiable {
    case simple, advanced

    var id: String { rawValue }
    var title: String { self == .simple ? "3 Bands" : "10 Bands" }
    var frequencies: [Double] {
        switch self {
        case .simple: [100, 1000, 10000]
        case .advanced: [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        }
    }
    var labels: [String] {
        switch self {
        case .simple: ["Bass", "Mid", "Treble"]
        case .advanced: ["31", "62", "125", "250", "500", "1k", "2k", "4k", "8k", "16k"]
        }
    }
}

enum EqualizerPreset: String, CaseIterable, Codable, Identifiable {
    case flat, bass, vocal, acoustic, bright, custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flat: "Flat"
        case .bass: "Bass Boost"
        case .vocal: "Vocals"
        case .acoustic: "Acoustic"
        case .bright: "Bright"
        case .custom: "Custom"
        }
    }

    func gains(for mode: EqualizerMode) -> [Double] {
        switch (self, mode) {
        case (.flat, .simple), (.custom, .simple): [0, 0, 0]
        case (.flat, .advanced), (.custom, .advanced): Array(repeating: 0, count: 10)
        case (.bass, .simple): [6, 2, -1]
        case (.bass, .advanced): [5, 5, 4, 3, 1, 0, -1, -1, -2, -2]
        case (.vocal, .simple): [-2, 4, 1]
        case (.vocal, .advanced): [-3, -2, -1, 0, 2, 4, 4, 3, 1, 0]
        case (.acoustic, .simple): [2, 0, 3]
        case (.acoustic, .advanced): [2, 2, 1, 0, -1, 0, 1, 2, 3, 3]
        case (.bright, .simple): [-2, 0, 5]
        case (.bright, .advanced): [-2, -2, -1, -1, 0, 1, 2, 3, 4, 5]
        }
    }
}

struct EqualizerSettings: Codable, Equatable {
    var enabled = false
    var mode: EqualizerMode = .simple
    var simplePreset: EqualizerPreset = .flat
    var advancedPreset: EqualizerPreset = .flat
    var simpleGains = EqualizerPreset.flat.gains(for: .simple)
    var advancedGains = EqualizerPreset.flat.gains(for: .advanced)

    var preset: EqualizerPreset { mode == .simple ? simplePreset : advancedPreset }
    var gains: [Double] { mode == .simple ? simpleGains : advancedGains }
    var frequencies: [Double] { mode.frequencies }

    mutating func selectMode(_ mode: EqualizerMode) { self.mode = mode }

    mutating func select(_ preset: EqualizerPreset) {
        guard preset != .custom else { return }
        if mode == .simple {
            simplePreset = preset
            simpleGains = preset.gains(for: .simple)
        } else {
            advancedPreset = preset
            advancedGains = preset.gains(for: .advanced)
        }
    }

    mutating func setGain(_ value: Double, at index: Int) {
        let value = min(12, max(-12, value))
        if mode == .simple {
            guard simpleGains.indices.contains(index) else { return }
            simpleGains[index] = value
            simplePreset = .custom
        } else {
            guard advancedGains.indices.contains(index) else { return }
            advancedGains[index] = value
            advancedPreset = .custom
        }
    }

    mutating func normalize() {
        if simpleGains.count != EqualizerMode.simple.frequencies.count {
            simpleGains = EqualizerPreset.flat.gains(for: .simple)
        }
        if advancedGains.count != EqualizerMode.advanced.frequencies.count {
            advancedGains = EqualizerPreset.flat.gains(for: .advanced)
        }
        simpleGains = simpleGains.map { $0.isFinite ? min(12, max(-12, $0)) : 0 }
        advancedGains = advancedGains.map { $0.isFinite ? min(12, max(-12, $0)) : 0 }
    }
}

/// A five-band parametric EQ for AVPlayerItem's decoded PCM audio.
/// Audio callbacks never access SwiftUI or PlayerController state.
final class EqualizerTapState {
    private struct Coefficients {
        var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0

        init(frequency: Double, gain: Double, sampleRate: Double) {
            guard abs(gain) > 0.001, sampleRate > 0 else { return }
            let frequency = min(frequency, sampleRate * 0.45)
            let omega = 2 * Double.pi * frequency / sampleRate
            let cosine = cos(omega)
            let alpha = sin(omega) / 2 // Q = 1
            let a = pow(10, gain / 40)
            let divisor = 1 + alpha / a
            b0 = (1 + alpha * a) / divisor
            b1 = -2 * cosine / divisor
            b2 = (1 - alpha * a) / divisor
            a1 = -2 * cosine / divisor
            a2 = (1 - alpha / a) / divisor
        }
    }

    private struct FilterState {
        var z1 = 0.0, z2 = 0.0
    }

    private let settingsLock = NSLock()
    private var settings: EqualizerSettings
    private var sampleRate = 44100.0
    private enum SampleType { case float32, float64, unsupported }
    private var sampleType: SampleType = .unsupported
    private var filters: [[FilterState]] = []
    private var smoothedGains: [Double] = []
    private var wasEnabled = false
    private var processedMode: EqualizerMode = .simple

    init(settings: EqualizerSettings) {
        self.settings = settings
    }

    func update(_ value: EqualizerSettings) {
        settingsLock.lock()
        settings = value
        settingsLock.unlock()
    }

    private func snapshot() -> EqualizerSettings {
        settingsLock.lock()
        let value = settings
        settingsLock.unlock()
        return value
    }

    func prepare(_ format: AudioStreamBasicDescription) {
        sampleRate = format.mSampleRate
        if format.mFormatID == kAudioFormatLinearPCM,
           format.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
            sampleType = format.mBitsPerChannel == 32 ? .float32
                : (format.mBitsPerChannel == 64 ? .float64 : .unsupported)
        } else {
            sampleType = .unsupported
        }
        processedMode = snapshot().mode
        filters = Array(repeating: Array(repeating: FilterState(), count: processedMode.frequencies.count),
                        count: Int(format.mChannelsPerFrame))
        smoothedGains = [Double](repeating: 0, count: processedMode.frequencies.count)
        wasEnabled = false
    }

    func process(_ buffers: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard sampleType != .unsupported, frames > 0 else { return }
        let current = snapshot()
        if current.mode != processedMode {
            processedMode = current.mode
            filters = Array(repeating: Array(repeating: FilterState(), count: current.frequencies.count),
                            count: filters.count)
            smoothedGains = [Double](repeating: 0, count: current.frequencies.count)
            wasEnabled = false
        }
        if !current.enabled {
            wasEnabled = false
            return
        }
        if !wasEnabled {
            for channel in filters.indices {
                filters[channel] = Array(repeating: FilterState(), count: current.frequencies.count)
            }
            smoothedGains = [Double](repeating: 0, count: current.frequencies.count)
            wasEnabled = true
        }

        let smoothing = min(1, Double(frames) / (sampleRate * 0.05))
        for band in smoothedGains.indices {
            smoothedGains[band] += (current.gains[band] - smoothedGains[band]) * smoothing
        }
        let coefficients = zip(current.frequencies, smoothedGains).map {
            Coefficients(frequency: $0.0, gain: $0.1, sampleRate: sampleRate)
        }
        let headroom = pow(10, -max(0, smoothedGains.max() ?? 0) / 20)

        var channelOffset = 0
        for buffer in UnsafeMutableAudioBufferListPointer(buffers) {
            switch sampleType {
            case .float32:
                processBuffer(buffer, frames: frames, channelOffset: channelOffset,
                              coefficients: coefficients, headroom: headroom, as: Float.self)
            case .float64:
                processBuffer(buffer, frames: frames, channelOffset: channelOffset,
                              coefficients: coefficients, headroom: headroom, as: Double.self)
            case .unsupported:
                break
            }
            channelOffset += Int(buffer.mNumberChannels)
        }
    }

    private func processBuffer<Sample: BinaryFloatingPoint>(
        _ buffer: AudioBuffer,
        frames: Int,
        channelOffset: Int,
        coefficients: [Coefficients],
        headroom: Double,
        as type: Sample.Type
    ) {
        guard let data = buffer.mData else { return }
        let channels = Int(buffer.mNumberChannels)
        guard channels > 0 else { return }
        let samples = min(frames, Int(buffer.mDataByteSize) / (MemoryLayout<Sample>.size * channels))
        let audio = data.assumingMemoryBound(to: Sample.self)
        for localChannel in 0..<channels {
            let channel = channelOffset + localChannel
            guard filters.indices.contains(channel) else { continue }
            for band in coefficients.indices {
                let coefficient = coefficients[band]
                var state = filters[channel][band]
                for frame in 0..<samples {
                    let position = frame * channels + localChannel
                    let input = Double(audio[position])
                    let output = coefficient.b0 * input + state.z1
                    state.z1 = coefficient.b1 * input - coefficient.a1 * output + state.z2
                    state.z2 = coefficient.b2 * input - coefficient.a2 * output
                    audio[position] = Sample(output)
                }
                filters[channel][band] = state
            }
            for frame in 0..<samples {
                let position = frame * channels + localChannel
                audio[position] *= Sample(headroom)
            }
        }
    }

    func makeTap() -> MTAudioProcessingTap? {
        let retained = Unmanaged.passRetained(self)
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: retained.toOpaque(),
            init: { _, clientInfo, storage in storage.pointee = clientInfo },
            finalize: { tap in
                Unmanaged<EqualizerTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                Unmanaged<EqualizerTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue().prepare(format.pointee)
            },
            unprepare: { _ in },
            process: { tap, frames, _, buffers, framesOut, flagsOut in
                var sourceFlags: MTAudioProcessingTapFlags = 0
                var received: CMItemCount = 0
                let status = MTAudioProcessingTapGetSourceAudio(tap, frames, buffers,
                                                                 &sourceFlags, nil, &received)
                framesOut.pointee = status == noErr ? received : 0
                flagsOut.pointee = sourceFlags
                guard status == noErr else { return }
                Unmanaged<EqualizerTapState>.fromOpaque(MTAudioProcessingTapGetStorage(tap))
                    .takeUnretainedValue().process(buffers, frames: received)
            }
        )
        #if compiler(>=6.4)
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                               kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        #else
        // Xcode 16 imports the Create-rule CF result as Unmanaged.
        var unmanagedTap: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks,
                                               kMTAudioProcessingTapCreationFlag_PostEffects, &unmanagedTap)
        let tap = unmanagedTap?.takeRetainedValue()
        #endif
        if status != noErr { retained.release() }
        return status == noErr ? tap : nil
    }
}
