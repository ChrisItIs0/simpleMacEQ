import AppKit
import EQCore
import SwiftUI

struct EQView: View {
    @ObservedObject var model: AppModel

    private var hasDevice: Bool { model.deviceUID != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            bands
                .opacity(model.profile.isEnabled ? 1 : 0.5)

            preamp
                .opacity(model.profile.isEnabled ? 1 : 0.5)

            Divider()

            footer
        }
        .padding(14)
        .frame(width: 600)
        .disabled(!hasDevice)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.deviceName)
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle(
                "EQ for this device",
                isOn: Binding(
                    get: { model.profile.isEnabled },
                    set: { model.setEnabled($0) }
                )
            )
            .toggleStyle(.switch)
        }
    }

    private var statusText: String {
        if !hasDevice { return "No output device found" }
        if model.isProcessing { return "Equalizer active" }
        if model.profile.isEnabled { return "Equalizer not running" }
        return "Audio is not modified on this device"
    }

    private var bands: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .trailing) {
                Text("+12")
                Spacer()
                Text("0")
                Spacer()
                Text("-12")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 150)

            ForEach(0..<EQBands.count, id: \.self) { band in
                VStack(spacing: 4) {
                    VerticalSlider(
                        value: Binding(
                            get: { model.profile.gains[band] },
                            set: { model.setGain(band: band, to: $0) }
                        ),
                        range: EQBands.gainRange
                    )
                    .frame(height: 150)

                    Text(EQBands.labels[band])
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text(gainText(model.profile.gains[band]))
                        .font(.system(size: 9).monospacedDigit())
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var preamp: some View {
        HStack {
            Text("Preamp")
                .font(.caption)
            Slider(
                value: Binding(
                    get: { model.profile.preampDB },
                    set: { model.setPreamp(($0 * 2).rounded() / 2) }
                ),
                in: EQBands.preampRange
            )
            Text("\(gainText(model.profile.preampDB)) dB")
                .font(.caption.monospacedDigit())
                .frame(width: 58, alignment: .trailing)
        }
    }

    private var footer: some View {
        HStack {
            Button("Reset") { model.resetBands() }
            Spacer()
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                )
            )
            .toggleStyle(.checkbox)
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    private func gainText(_ gain: Double) -> String {
        if abs(gain) < 0.05 { return "0" }
        return String(format: "%+.1f", gain)
    }
}

/// A vertical slider that snaps to 0.5 steps.
struct VerticalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    private let knobSize: CGFloat = 14

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let travel = max(height - knobSize, 1)
            let span = range.upperBound - range.lowerBound
            let fraction = (value - range.lowerBound) / span
            let knobY = knobSize / 2 + travel * (1 - fraction)

            ZStack {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 4, height: travel)
                    .position(x: geometry.size.width / 2, y: height / 2)

                Rectangle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 12, height: 1)
                    .position(x: geometry.size.width / 2, y: height / 2)

                Circle()
                    .fill(Color.accentColor)
                    .frame(width: knobSize, height: knobSize)
                    .position(x: geometry.size.width / 2, y: knobY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { gesture in
                    let position = (gesture.location.y - knobSize / 2) / travel
                    let clamped = 1 - min(max(position, 0), 1)
                    let raw = range.lowerBound + Double(clamped) * span
                    value = (raw * 2).rounded() / 2
                }
            )
        }
    }
}
