import Foundation

struct LabsSettingsStore {
    func isLocalQwenEnabled() -> Bool {
        false
    }

    func setLocalQwenEnabled(_: Bool) {
        // Legacy no-op. Local MLC/Qwen support has been removed.
    }
}
