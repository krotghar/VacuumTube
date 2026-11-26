import SwiftUI
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    // A scene session saved by the earlier SwiftUI build comes back with SwiftUI's own delegate and stays black; take it over.
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        NotificationCenter.default.addObserver(self, selector: #selector(sceneWillConnect(_:)), name: UIScene.willConnectNotification, object: nil)
        return true
    }

    @objc private func sceneWillConnect(_ note: Notification) {
        guard let scene = note.object as? UIWindowScene, !(scene.delegate is SceneDelegate) else { return }
        let delegate = SceneDelegate()
        scene.delegate = delegate
        delegate.attach(to: scene)
    }

    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        attach(to: scene)
    }

    func attach(to scene: UIWindowScene) {
        guard window == nil else { return }
        let window = UIWindow(windowScene: scene)
        window.backgroundColor = Shell.backgroundColor
        window.rootViewController = RootController(rootView: AnyView(LeanbackView().ignoresSafeArea()))
        window.makeKeyAndVisible()
        self.window = window
    }
}

final class RootController: UIHostingController<AnyView> {
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Shell.backgroundColor
    }
}
