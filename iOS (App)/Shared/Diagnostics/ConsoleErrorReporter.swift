import Foundation

enum ConsoleErrorReporter {
    static func logInfo(_ message: String, context: String, metadata: [String: String] = [:]) {
        print("=== INFO [\(context)] ===")
        if !metadata.isEmpty {
            for key in metadata.keys.sorted() {
                if let value = metadata[key] {
                    print("[meta] \(key)=\(value)")
                }
            }
        }
        print(message)
        print("=== END INFO [\(context)] ===")
    }

    static func log(_ error: Error, context: String, metadata: [String: String] = [:]) {
        print("=== ERROR [\(context)] ===")

        if !metadata.isEmpty {
            for key in metadata.keys.sorted() {
                if let value = metadata[key] {
                    print("[meta] \(key)=\(value)")
                }
            }
        }

        print("[localized] \(error.localizedDescription)")
        print("[reflecting] \(String(reflecting: error))")

        var visited = Set<ObjectIdentifier>()
        dumpNSError(error as NSError, label: "root", visited: &visited, depth: 0)

        print("=== END ERROR [\(context)] ===")
    }

    static func logMessage(_ message: String, context: String, metadata: [String: String] = [:]) {
        print("=== LOG [\(context)] ===")
        if !metadata.isEmpty {
            for key in metadata.keys.sorted() {
                if let value = metadata[key] {
                    print("[meta] \(key)=\(value)")
                }
            }
        }
        print(message)
        print("=== END LOG [\(context)] ===")
    }

    private static func dumpNSError(
        _ error: NSError,
        label: String,
        visited: inout Set<ObjectIdentifier>,
        depth: Int
    ) {
        let identifier = ObjectIdentifier(error)
        guard visited.insert(identifier).inserted else { return }

        let indent = String(repeating: "  ", count: depth)
        print("\(indent)[\(label)] domain=\(error.domain) code=\(error.code)")

        if !error.userInfo.isEmpty {
            for (key, value) in error.userInfo {
                if key == NSUnderlyingErrorKey, let underlying = value as? NSError {
                    dumpNSError(
                        underlying,
                        label: "underlying",
                        visited: &visited,
                        depth: depth + 1
                    )
                    continue
                }

                if key == NSMultipleUnderlyingErrorsKey, let underlying = value as? [NSError] {
                    for (index, nested) in underlying.enumerated() {
                        dumpNSError(
                            nested,
                            label: "underlying[\(index)]",
                            visited: &visited,
                            depth: depth + 1
                        )
                    }
                    continue
                }

                print("\(indent)  [userInfo] \(key)=\(String(reflecting: value))")
            }
        }
    }
}
