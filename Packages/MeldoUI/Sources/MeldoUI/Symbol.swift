import SwiftUI

public extension Image {
    /// An SF Symbol, or one of Meldo's own symbols when the name starts with "meldo."
    /// (custom symbols in Shared/Glyphs.xcassets, compiled into the app and the widgets).
    init(symbol name: String) {
        if name.hasPrefix("meldo.") {
            self.init(name)
        } else {
            self.init(systemName: name)
        }
    }
}

public extension Label where Title == Text, Icon == Image {
    /// Like `Label(_:systemImage:)`, but also takes Meldo's own symbols.
    init(_ title: some StringProtocol, symbol name: String) {
        self.init { Text(title) } icon: { Image(symbol: name) }
    }
}
