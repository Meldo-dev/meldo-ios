import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

extension MeldoFeature {
    /// Fächer, and the subject editor other screens open.
    static var subjects: MeldoFeature {
        var feature = MeldoFeature(id: "subjects", title: { L("Fächer") }, symbol: "books.vertical", placement: .app) {
            SubjectListView()
        }
        feature.destination = { route in
            route == .newSubject ? AnyView(SubjectEditorView(subject: nil)) : nil
        }
        return feature
    }
}
