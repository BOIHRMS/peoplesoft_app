import UIKit
import Flutter

@objc class AppDelegate: FlutterAppDelegate {
  private var blurView: UIVisualEffectView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    DispatchQueue.main.async { self.enableScreenProtection() }
    return result
  }

  // Makes screenshots and recordings come out black
  private func enableScreenProtection() {
    guard let window = self.window else { return }
    let field = UITextField()
    field.isSecureTextEntry = true
    field.isUserInteractionEnabled = false
    field.translatesAutoresizingMaskIntoConstraints = false
    window.addSubview(field)
    field.centerYAnchor.constraint(equalTo: window.centerYAnchor).isActive = true
    field.centerXAnchor.constraint(equalTo: window.centerXAnchor).isActive = true
    window.layer.superlayer?.addSublayer(field.layer)
    field.layer.sublayers?.first?.addSublayer(window.layer)
  }

  // Blurs the app in the app switcher
  override func applicationWillResignActive(_ application: UIApplication) {
    guard let window = self.window else { return }
    let blur = UIVisualEffectView(effect: UIBlurEffect(style: .light))
    blur.frame = window.bounds
    window.addSubview(blur)
    blurView = blur
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    blurView?.removeFromSuperview()
    blurView = nil
  }
}