import MeldoKit
import MeldoState
import MeldoUI
import SwiftUI

extension MeldoFeature {
    /// Dokumente: scanned and imported PDFs by subject.
    public static var exams: MeldoFeature {
        var feature = MeldoFeature(id: "exams", title: { L("Dokumente") }, symbol: "doc.on.doc", placement: .bar) {
            ExamListView()
        }
        feature.alwaysInWideBar = true
        return feature
    }
}
