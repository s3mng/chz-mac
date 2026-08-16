# Cracker

맥용 치지직 라이브 녹화 · 다시보기 저장 앱입니다.

네이버 로그인 쿠키는 키체인에만 두고, 외부로 보내지 않습니다.

## 요구사항

- macOS 14 이상
- Xcode 16 이상

## 실행

```sh
open Cracker.xcodeproj
```

Xcode에서 `Cracker` 스킴으로 Run 하면 됩니다.

기본 저장 위치는 `Movies/cracker` 입니다.

## 배포

GitHub 기본 러너는 Linux라 이 앱은 거기서 못 만듭니다. 워크플로는 `macos-15`(Apple Silicon)에서 `arm64`만 빌드합니다. Intel 맥은 대상이 아닙니다.

`v*` 태그를 푸시하면 Release DMG가 올라갑니다. 메인 푸시와 수동 실행은 아티팩트만 올립니다.

서명·공증은 넣지 않아서, 받은 맥에서는 처음 한 번 우클릭 → 열기가 필요할 수 있습니다.

## 절전

다운로드가 켜져 있는 동안 `ProcessInfo.beginActivity(.idleSystemSleepDisabled)` 로 자동 절전만 막습니다. `caffeinate -i` 와 같은 IOPM assertion입니다. 화면을 켜 두거나, 덮개를 닫아도 깨워 두지는 않습니다.

## 캐시

다시보기(VOD)를 받다가 끊기면 조각은 앱 캐시에 남고, 설정에서 지울 수 있습니다. 라이브는 끊기거나 멈추면 그때까지 받은 파일을 바로 저장 폴더로 옮깁니다.

## 주의사항

앱으로 저장한 영상의 저작권과 치지직 이용약관 준수 책임은 사용자에게 있습니다.

## License

MIT
