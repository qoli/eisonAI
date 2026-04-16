import Foundation
import SwiftUI

struct InstalledMemoryView: View {
    let ramGiBOverride: Double?
    private let modelStore = MLXModelStore()

    init(ramGiBOverride: Double? = nil) {
        self.ramGiBOverride = ramGiBOverride
    }

    private enum RamTier {
        case insufficient
        case limited
        case sufficient
    }

    private var ramGiB: Double {
        if let override = ramGiBOverride {
            return override
        }
        return Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024 / 1024
    }

    private var ramDisplay: String {
        String(format: "%.1f GiB", ramGiB)
    }

    private var ramTier: RamTier {
        if ramGiB < 6 {
            return .insufficient
        }
        if ramGiB <= 8 {
            return .limited
        }
        return .sufficient
    }

    private var appleAvailable: Bool {
        AppleIntelligenceAvailability.currentStatus() == .available
    }

    private var selectedMLXModelID: String? {
        modelStore.loadSelectedModelID()
    }

    private var ramLevelColors: [Color] {
        if ramGiB < 6 {
            return [.gray, .gray, .red]
        }
        if ramGiB < 8 {
            return [.gray, .yellow, .green]
        }
        if ramGiB < 16 {
            return [.gray, .green, .green]
        }
        return [.green, .green, .green]
    }

    private var ramMessage: String {
        if appleAvailable {
            return "Apple Intelligence is available for local runs."
        }
        if let selectedMLXModelID {
            switch ramTier {
            case .insufficient:
                return "\(selectedMLXModelID) is configured, but this device is likely better suited to BYOK."
            case .limited:
                return "\(selectedMLXModelID) may run, but memory pressure can be high."
            case .sufficient:
                return "\(selectedMLXModelID) should be usable as a local MLX model."
            }
        }
        switch ramTier {
        case .insufficient:
            return "This device isn’t suited for larger local MLX models. We recommend BYOK."
        case .limited:
            return "Smaller MLX models may run, but choose cautiously."
        case .sufficient:
            return "This device can support local MLX models."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Installed Memory")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.semibold)

                Spacer()
            }

            HStack {
                Text(ramDisplay)
                    .font(.title)
                    .fontWeight(.bold)
                    .fontDesign(.rounded)

                Spacer()

                VStack(spacing: 2) {
                    ForEach(0 ..< 3, id: \.self) { index in
                        Capsule()
                            .fill(ramLevelColors[index])
                            .frame(width: 16, height: 5)
                    }
                }
            }

            Text(ramMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
//        .glassedEffect(in: RoundedRectangle(cornerRadius: 20), interactive: true)
    }
}

#Preview {
    InstalledMemoryView(ramGiBOverride: 8)
        .padding()
}
