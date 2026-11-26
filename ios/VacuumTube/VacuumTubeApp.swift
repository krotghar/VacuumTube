import SwiftUI

@main
struct VacuumTubeApp: App {
    var body: some Scene {
        WindowGroup {
            LeanbackView()
                .ignoresSafeArea()
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
                .background(Color(Shell.backgroundColor))
        }
    }
}
