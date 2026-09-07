import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // google_maps_flutter(iOS)는 앱 시작 시 API 키를 직접 등록해야 한다.
    // 키 원문은 저장소에 커밋하지 않는다 — Info.plist 의 `MapsApiKey` 값이
    // 빌드 설정 `$(MAPS_API_KEY)` 로 치환되고, 그 값은 xcconfig
    // (ios/Flutter/Maps.xcconfig, gitignore됨 — Maps.xcconfig.example 참고,
    // Debug/Release.xcconfig 가 `#include?` 로 연결) 또는 CI 빌드 설정에서
    // 주입한다. 값이 비어 있으면(치환 안 됨/빈 문자열) 지도가 회색으로 뜨지만
    // 앱은 정상 기동한다.
    if let mapsApiKey = Bundle.main.object(forInfoDictionaryKey: "MapsApiKey") as? String,
       !mapsApiKey.isEmpty,
       mapsApiKey != "$(MAPS_API_KEY)" {
      GMSServices.provideAPIKey(mapsApiKey)
    } else {
      NSLog("[곁에] MAPS_API_KEY 가 설정되지 않아 지도가 표시되지 않습니다. " +
        "ios/Flutter/Maps.xcconfig 를 설정하세요.")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
