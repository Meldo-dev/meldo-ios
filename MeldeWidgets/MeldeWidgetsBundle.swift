import SwiftUI
import WidgetKit

@main
struct MeldeWidgetsBundle: WidgetBundle {
    var body: some Widget {
        MeldoTodayWidget()
        MeldoStatsWidget()
        TodayScheduleWidget()
        HomeworkWidget()
        HolidayCountdownWidget()
        MeldenControl()
        LessonLiveActivity()
    }
}
