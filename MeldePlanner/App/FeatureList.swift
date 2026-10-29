import MeldoCalendar
import MeldoDashboard
import MeldoDrive
import MeldoExams
import MeldoGrades
import MeldoKit
import MeldoOnboarding
import MeldoParticipation
import MeldoSettings
import MeldoState
import MeldoStatistics
import MeldoSubjects
import MeldoTasks
import MeldoTeams
import MeldoTimetable
import MeldoUI
import SwiftUI

extension MeldoFeatures {
    /// The features this build contains, in navigation order. To leave one out, remove its
    /// line here and its package from project.yml; its tabs, rows, cards and links go with it.
    static let app = MeldoFeatures([
        .dashboard,
        .timetable,
        .participation,
        .tasks,
        .grades,
        .calendar,
        .statistics,
        .exams,
        .teams,
        .drive,
        .subjects,
        .settings,
        .status,
        .about,
        .onboarding,
    ])
}
