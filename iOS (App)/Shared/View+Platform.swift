import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

extension View {
    @ViewBuilder
    func ifIPad<Content: View>(
        @ViewBuilder _ transform: (Self) -> Content
    ) -> some View {
        #if targetEnvironment(macCatalyst)
            self
        #else
            #if canImport(UIKit)
                if UIDevice.current.userInterfaceIdiom == .pad {
                    transform(self)
                } else {
                    self
                }
            #else
                self
            #endif
        #endif
    }

    @ViewBuilder
    func ifIPhone<Content: View>(
        @ViewBuilder _ transform: (Self) -> Content
    ) -> some View {
        #if targetEnvironment(macCatalyst)
            self
        #else
            #if canImport(UIKit)
                if UIDevice.current.userInterfaceIdiom == .phone {
                    transform(self)
                } else {
                    self
                }
            #else
                self
            #endif
        #endif
    }

    @ViewBuilder
    func ifMacCatalyst<Content: View>(
        @ViewBuilder _ transform: (Self) -> Content
    ) -> some View {
        #if targetEnvironment(macCatalyst)
            transform(self)
        #else
            self
        #endif
    }
}
