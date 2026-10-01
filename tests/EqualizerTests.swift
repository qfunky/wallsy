import Foundation
import AudioToolbox

@main
struct EqualizerTests {
    static func main() {
        let sampleRate = 44_100.0
        let frames = 44_100
        let format = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        func render(frequency: Double, settings: EqualizerSettings) -> [Float] {
            var samples = [Float](repeating: 0, count: frames * 2)
            for frame in 0..<frames {
                let value = Float(0.1 * sin(2 * Double.pi * frequency * Double(frame) / sampleRate))
                samples[frame * 2] = value
                samples[frame * 2 + 1] = value
            }
            let state = EqualizerTapState(settings: settings)
            state.prepare(format)
            samples.withUnsafeMutableBufferPointer { pointer in
                var buffers = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(
                        mNumberChannels: 2,
                        mDataByteSize: UInt32(frames * 2 * MemoryLayout<Float>.size),
                        mData: pointer.baseAddress
                    )
                )
                withUnsafeMutablePointer(to: &buffers) { state.process($0, frames: frames) }
            }
            return samples
        }

        func rms(_ samples: [Float]) -> Double {
            let tail = samples.dropFirst(samples.count / 2)
            return sqrt(tail.reduce(0.0) { $0 + Double($1 * $1) } / Double(tail.count))
        }

        let flat = EqualizerSettings()
        let untouched = render(frequency: 100, settings: flat)
        assert(abs(rms(untouched) - 0.1 / sqrt(2)) < 0.001, "Bypass changed the signal")

        var bass = EqualizerSettings()
        bass.enabled = true
        bass.select(.bass)
        let boosted = render(frequency: 100, settings: bass)
        assert(rms(boosted) > rms(untouched) * 1.25, "Bass preset did not boost 100 Hz")
        assert(boosted.allSatisfy(\.isFinite), "Equalizer produced non-finite samples")

        var highResolution = [Double](repeating: 0, count: frames * 2)
        for frame in 0..<frames {
            let value = 0.1 * sin(2 * Double.pi * 100 * Double(frame) / sampleRate)
            highResolution[frame * 2] = value
            highResolution[frame * 2 + 1] = value
        }
        var doubleFormat = format
        doubleFormat.mBitsPerChannel = 64
        doubleFormat.mBytesPerPacket = 16
        doubleFormat.mBytesPerFrame = 16
        let doubleState = EqualizerTapState(settings: bass)
        doubleState.prepare(doubleFormat)
        highResolution.withUnsafeMutableBufferPointer { pointer in
            var buffers = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(mNumberChannels: 2,
                                      mDataByteSize: UInt32(frames * 2 * MemoryLayout<Double>.size),
                                      mData: pointer.baseAddress)
            )
            withUnsafeMutablePointer(to: &buffers) { doubleState.process($0, frames: frames) }
        }
        let doubleRMS = sqrt(highResolution.dropFirst(frames).reduce(0) { $0 + $1 * $1 } / Double(frames))
        assert(doubleRMS > 0.1 / sqrt(2) * 1.25, "64-bit audio was not equalized")

        bass.selectMode(.advanced)
        bass.select(.bright)
        assert(bass.gains.count == 10, "Advanced mode must have ten bands")
        bass.selectMode(.simple)
        assert(bass.gains == EqualizerPreset.bass.gains(for: .simple), "Mode switching lost three-band settings")

        var malformed = EqualizerSettings()
        malformed.simpleGains = [Double.nan]
        malformed.normalize()
        assert(malformed.gains == [0, 0, 0], "Invalid saved settings were not repaired")
        print("Equalizer DSP tests passed")
    }
}
