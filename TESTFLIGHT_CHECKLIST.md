# Magic Bottle TestFlight Checklist

## 배포 전 체크

- `flutter analyze`
- `flutter test`
- 실제 iPhone 기기에서 터치, 힌트, 언두, 스테이지 클리어 확인
- iPhone SE, 기본형, Pro Max 급 화면에서 레이아웃 확인
- 사운드 에셋을 추가했다면 무음 모드/볼륨 상태 확인

## iOS 설정 확인

- 세로 모드만 지원하도록 `Info.plist` 반영 완료
- `ITSAppUsesNonExemptEncryption = false` 설정 완료
- 앱 이름은 `Magic Bottle`
- 런치 스크린과 앱 아이콘은 커스텀 에셋 반영 완료

## Xcode에서 해야 할 일

1. `ios/Runner.xcworkspace` 열기
2. `Signing & Capabilities`에서 Team 선택
3. Bundle Identifier를 고유 값으로 변경
4. Version / Build 번호 설정
5. 실제 iPhone 연결 후 1회 실행
6. `Product > Archive`
7. Organizer에서 `Distribute App > App Store Connect > Upload`

## App Store Connect 준비물

- 앱 이름: `Magic Bottle`
- 부제 예시: `Fantasy Color Sort Puzzle`
- 설명문
- 키워드
- 개인정보 처리방침 URL
- 지원 URL
- 카테고리: `Games / Puzzle`

## 스크린샷 권장 구성

1. 메인 플레이 화면
2. 힌트 사용 장면
3. 언두 버튼 사용 장면
4. 스테이지 선택 화면
5. 스테이지 클리어 팝업 화면

## 권장 다음 작업

- 실제 효과음 파일 추가
- 앱 아이콘 최종 브랜딩 버전 교체
- App Store 설명문과 프로모션 문구 작성
