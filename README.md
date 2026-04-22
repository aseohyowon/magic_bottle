# Magic Bottle

Flutter + Flame 기반으로 만든 iOS 우선 색상 정렬 퍼즐 게임 프로토타입입니다.  
`Magic Sort` 스타일의 플레이를 목표로 하며, 여러 튜브에 섞여 있는 색상 구슬을 옮겨서 같은 색끼리 정렬하면 스테이지를 클리어합니다.

## 주요 특징

- Flutter + Flame 기반 단일 화면 퍼즐 플레이
- 세로 모드 중심 iOS 우선 레이아웃
- 1~10 스테이지 정의
- 해결 가능한 퍼즐 생성
- 언두, 힌트, 별점, 진행도 저장 지원
- 반투명 유리 튜브 / 네온 오브 / 판타지 배경 연출

## 프로젝트 구조

- 게임 핵심 로직: `lib/main.dart`
- iOS 아이콘: `ios/Runner/Assets.xcassets/AppIcon.appiconset`
- iOS 런치 스크린: `ios/Runner/Base.lproj/LaunchScreen.storyboard`
- TestFlight 준비 문서: `TESTFLIGHT_CHECKLIST.md`

## 실행 방법

```bash
cd C:\Users\seo\gitHubCode\magic_bottle
flutter pub get
flutter run
```

## 품질 확인 명령어

```bash
flutter analyze
flutter test
```

## iOS 빌드

Windows에서는 iOS 빌드를 직접 실행할 수 없으므로 macOS + Xcode 환경이 필요합니다.

```bash
flutter pub get
flutter build ios
```

실제 배포 직전에는 Xcode에서 `ios/Runner.xcworkspace`를 열고 서명, Bundle Identifier, 버전 번호를 확인하는 흐름을 권장합니다.

## 현재 포함된 iOS 준비 사항

- 커스텀 앱 아이콘 반영
- 커스텀 런치 스크린 반영
- 세로 모드 전용 설정
- TestFlight 업로드 전 체크리스트 문서 포함

## 다음 추천 작업

1. 실제 효과음 파일 추가
2. 앱 아이콘 최종 브랜딩 버전 교체
3. App Store 설명문 / 키워드 / 스크린샷 제작
4. 실제 iPhone에서 터치감과 난이도 밸런스 테스트
