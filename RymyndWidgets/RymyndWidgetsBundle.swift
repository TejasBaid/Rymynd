import SwiftUI
import WidgetKit

@main
struct RymyndWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ReminderLiveActivity()
        AlarmLiveActivity()
    }
}
