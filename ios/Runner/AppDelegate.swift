import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var blurView: UIVisualEffectView?
  private let secureField = UITextField()

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
    secureField.isSecureTextEntry = true
    secureField.isUserInteractionEnabled = false
    secureField.translatesAutoresizingMaskIntoConstraints = false
    window.addSubview(secureField)
    secureField.centerYAnchor.constraint(equalTo: window.centerYAnchor).isActive = true
    secureField.centerXAnchor.constraint(equalTo: window.centerXAnchor).isActive = true
    window.layer.superlayer?.addSublayer(secureField.layer)
    if #available(iOS 17.0, *) {
      secureField.layer.sublayers?.first?.addSublayer(window.layer)
    } else {
      secureField.layer.sublayers?.last?.addSublayer(window.layer)
    }
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