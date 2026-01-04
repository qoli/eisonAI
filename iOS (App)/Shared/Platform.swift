import Foundation
#if canImport(UIKit)
    import UIKit
#endif

enum Platform {
    case iPad
    case iPhone
    case macCatalyst
}

func currentPlatform() -> Platform {
    #if targetEnvironment(macCatalyst)
        return .macCatalyst
    #else
        #if canImport(UIKit)
            switch UIDevice.current.userInterfaceIdiom {
            case .pad:
                return .iPad
            case .phone:
                return .iPhone
            default:
                return .iPhone
            }
        #else
            return .iPhone
        #endif
    #endif
}

var platform: Platform {
    currentPlatform()
}
