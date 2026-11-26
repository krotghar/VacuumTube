import SwiftUI

@main
struct VacuumTubeApp: App {
    var body: some Scene {
        WindowGroup {
            LeanbackView()
                .ignoresSafeArea()
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
                // The first swipe from a side edge is our back gesture; Stage Manager and the system get the second one.
                .defersSystemGestures(on: .horizontal)
                .background(Color(Shell.backgroundColor))
        }
    }
}
