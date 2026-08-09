# osmPod

SwiftUI + SwiftData で構築した iOS 向けポッドキャスト管理アプリの初期土台です。

## 構成

- `App/`: App エントリ (`osmPodApp`)
- `Models/`: SwiftData `@Model` 定義（`Show`, `Episode`, `Group`）
- `Services/`: 番組登録処理（RSS URL の簡易バリデーション）
- `Views/`: メイン画面、番組追加画面
- `osmPod.xcodeproj`: Xcode プロジェクト

## データモデル

- `Show` 1 - N `Episode`
- `Group` N - N `Show`
- `Group` N - N `Episode`

## 起動方法

1. Xcode で `osmPod.xcodeproj` を開く
2. Target `osmPod` を選択
3. 任意の iOS Simulator で実行
