import Foundation

/// The fixed band layout of the equalizer: 16 peaking bands spaced 2/3 octave apart.
public enum EQBands {
    public static let frequencies: [Double] = [
        20, 32, 50, 80, 125, 200, 315, 500,
        800, 1250, 2000, 3150, 5000, 8000, 12500, 20000,
    ]

    public static let labels: [String] = [
        "20", "32", "50", "80", "125", "200", "315", "500",
        "800", "1.25k", "2k", "3.15k", "5k", "8k", "12.5k", "20k",
    ]

    public static let count = frequencies.count

    /// Q of a 2/3-octave wide peaking filter.
    public static let q = 2.14

    /// Allowed band gain in dB.
    public static let gainRange: ClosedRange<Double> = -12...12

    /// Allowed preamp gain in dB.
    public static let preampRange: ClosedRange<Double> = -12...12
}
