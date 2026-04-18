import OSLog

extension Logger {
    func xcodeDebug(_ message: @autoclosure () -> String) {
        let value = message()
        debug("\(value, privacy: .public)")
        mirrorToXcodeConsole(level: "debug", message: value)
    }

    func xcodeNotice(_ message: @autoclosure () -> String) {
        let value = message()
        notice("\(value, privacy: .public)")
        mirrorToXcodeConsole(level: "notice", message: value)
    }

    func xcodeWarning(_ message: @autoclosure () -> String) {
        let value = message()
        warning("\(value, privacy: .public)")
        mirrorToXcodeConsole(level: "warning", message: value)
    }

    func xcodeError(_ message: @autoclosure () -> String) {
        let value = message()
        error("\(value, privacy: .public)")
        mirrorToXcodeConsole(level: "error", message: value)
    }

    private func mirrorToXcodeConsole(level: String, message: String) {
        #if DEBUG
            print("[Logger.\(level)] \(message)")
        #endif
    }
}
