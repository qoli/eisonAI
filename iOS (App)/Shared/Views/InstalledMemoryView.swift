import Foundation
import SwiftUI

struct InstalledMemoryView: View {
    let ramGiBOverride: Double?

    @AppStorage(AppConfig.localQwenEnabledKey, store: UserDefaults(suiteName: AppConfig.appGroupIdentifier))
    private var localQwenEnabled = false

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
        if !localQwenEnabled {
            return "Local models are off. Enable Qwen3 0.6B in Settings → Labs."
        }
        switch ramTier {
        case .insufficient:
            return "This device isn’t suited for local models. We recommend BYOK."
        case .limited:
            return "Local Qwen3 0.6B may run but can be unstable."
        case .sufficient:
            return "This device can run Qwen3 0.6B locally."
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
        .glassedEffect(in: RoundedRectangle(cornerRadius: 20), interactive: true)
    }
}

#Preview {
    InstalledMemoryView(ramGiBOverride: 8)
        .padding()
}
