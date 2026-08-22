import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // google_maps_flutter(iOS)는 앱 시작 시 API 키를 직접 등록해야 한다.
    // 가정(assumption): 실제 키는 비밀값이라 커밋하지 않는다 — 배포 전
    // "YOUR_GOOGLE_MAPS_API_KEY"를 실제 키로 교체할 것(android/app/src/main/
    // AndroidManifest.xml의 동일 플레이스홀더와 짝을 이룬다).
    GMSServices.provideAPIKey("YOUR_GOOGLE_MAPS_API_KEY")
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
