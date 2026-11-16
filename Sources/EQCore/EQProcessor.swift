import Foundation
import os

/// A 16-band stereo peaking equalizer (cascaded biquads).
///
/// `setParameters` may be called from any thread. `syncParameters` and `process`
/// are meant for the realtime audio thread: they never allocate and never block.
public final class EQProcessor {
    public static let channelCount = 2

    public let sampleRate: Double

    private let bandCount = EQBands.count

    // State owned by the audio thread.
    private let coefficients: UnsafeMutablePointer<Double>   // bandCount * 5: b0 b1 b2 a1 a2
    private let bandActive: UnsafeMutablePointer<Bool>       // bandCount
    private let filterState: UnsafeMutablePointer<Double>    // channelCount * bandCount * 2
    private var preamp: Float = 1

    // Handoff area, guarded by `lock`.
    private let pendingCoefficients: UnsafeMutablePointer<Double>
    private let pendingActive: UnsafeMutablePointer<Bool>
    private var pendingPreamp: Float = 1
    private var dirty = false
    private let lock: UnsafeMutablePointer<os_unfair_lock>

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate

        coefficients = .allocate(capacity: bandCount * 5)
        coefficients.initialize(repeating: 0, count: bandCount * 5)
        pendingCoefficients = .allocate(capacity: bandCount * 5)
        pendingCoefficients.initialize(repeating: 0, count: bandCount * 5)

        bandActive = .allocate(capacity: bandCount)
        bandActive.initialize(repeating: false, count: bandCount)
        pendingActive = .allocate(capacity: bandCount)
        pendingActive.initialize(repeating: false, count: bandCount)

        let stateCount = Self.channelCount * bandCount * 2
        filterState = .allocate(capacity: stateCount)
        filterState.initialize(repeating: 0, count: stateCount)

        lock = .allocate(capacity: 1)
        lock.initialize(to: os_unfair_lock())
    }

    deinit {
        coefficients.deallocate()
        pendingCoefficients.deallocate()
        bandActive.deallocate()
        pendingActive.deallocate()
        filterState.deallocate()
        lock.deallocate()
    }

    /// Sets the band gains and preamp (both in dB). Missing bands are treated as 0 dB.
    public func setParameters(gains: [Double], preampDB: Double) {
        var newCoefficients = [Double](repeating: 0, count: bandCount * 5)
        var newActive = [Bool](repeating: false, count: bandCount)

        for band in 0..<bandCount {
            let gain = band < gains.count ? gains[band] : 0
            guard abs(gain) > 0.01 else { continue }
            let c = Self.peakingCoefficients(
                frequency: EQBands.frequencies[band],
                gainDB: gain,
                q: EQBands.q,
                sampleRate: sampleRate
            )
            newCoefficients[band * 5 + 0] = c.b0
            newCoefficients[band * 5 + 1] = c.b1
            newCoefficients[band * 5 + 2] = c.b2
            newCoefficients[band * 5 + 3] = c.a1
            newCoefficients[band * 5 + 4] = c.a2
            newActive[band] = true
        }

        let newPreamp = Float(pow(10, preampDB / 20))

        os_unfair_lock_lock(lock)
        for i in 0..<(bandCount * 5) { pendingCoefficients[i] = newCoefficients[i] }
        for i in 0..<bandCount { pendingActive[i] = newActive[i] }
        pendingPreamp = newPreamp
        dirty = true
        os_unfair_lock_unlock(lock)
    }

    /// Picks up the latest parameters. Call once per render cycle on the audio thread.
    public func syncParameters() {
        guard os_unfair_lock_trylock(lock) else { return }
        if dirty {
            for i in 0..<(bandCount * 5) { coefficients[i] = pendingCoefficients[i] }
            for band in 0..<bandCount {
                bandActive[band] = pendingActive[band]
                if !pendingActive[band] {
                    for channel in 0..<Self.channelCount {
                        let s = filterState + (channel * bandCount + band) * 2
                        s[0] = 0
                        s[1] = 0
                    }
                }
            }
            preamp = pendingPreamp
            dirty = false
        }
        os_unfair_lock_unlock(lock)
    }

    /// Filters one channel in place. `stride` is the distance between successive
    /// samples of this channel (1 for planar data, the channel count for interleaved).
    public func process(channel: Int, data: UnsafeMutablePointer<Float>, stride: Int, frames: Int) {
        guard channel >= 0, channel < Self.channelCount, frames > 0, stride > 0 else { return }

        if preamp != 1 {
            var index = 0
            for _ in 0..<frames {
                data[index] *= preamp
                index += stride
            }
        }

        for band in 0..<bandCount where bandActive[band] {
            let c = coefficients + band * 5
            let b0 = c[0], b1 = c[1], b2 = c[2], a1 = c[3], a2 = c[4]
            let s = filterState + (channel * bandCount + band) * 2
            var z1 = s[0]
            var z2 = s[1]

            // Transposed direct form II.
            var index = 0
            for _ in 0..<frames {
                let x = Double(data[index])
                let y = b0 * x + z1
                z1 = b1 * x - a1 * y + z2
                z2 = b2 * x - a2 * y
                data[index] = Float(y)
                index += stride
            }

            // Keep decaying tails out of the denormal range.
            if abs(z1) < 1e-25 { z1 = 0 }
            if abs(z2) < 1e-25 { z2 = 0 }
            s[0] = z1
            s[1] = z2
        }
    }

    /// RBJ audio EQ cookbook peaking filter, normalized so that a0 == 1.
    static func peakingCoefficients(
        frequency: Double,
        gainDB: Double,
        q: Double,
        sampleRate: Double
    ) -> (b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        let clampedFrequency = min(frequency, sampleRate * 0.49)
        let a = pow(10, gainDB / 40)
        let w0 = 2 * Double.pi * clampedFrequency / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosW0 = cos(w0)

        let a0 = 1 + alpha / a
        return (
            b0: (1 + alpha * a) / a0,
            b1: (-2 * cosW0) / a0,
            b2: (1 - alpha * a) / a0,
            a1: (-2 * cosW0) / a0,
            a2: (1 - alpha / a) / a0
        )
    }
}
