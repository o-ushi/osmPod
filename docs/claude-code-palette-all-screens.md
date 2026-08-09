# osmPod — 全画面カラーを osmGradus と同一にする作業指示書

このファイルは、Claude Code に **全画面の色彩を osmGradus と揃える作業** をさせるためのプロンプトです。

## 使い方（人間 → Claude Code）

Claude Code に、次のように指示してください。

```text
docs/claude-code-palette-all-screens.md を読んで、書いてある通りに実施して。
完了後は実施内容の要約だけ報告して。
```

段階的に進めたい場合:

```text
docs/claude-code-palette-all-screens.md の「作業手順」1（調査）だけ実施して。
コード変更はしない。ヒット一覧だけ報告して。
```

```text
docs/claude-code-palette-all-screens.md の「作業手順」2〜3（共通コンポーネント＋SettingsView）だけ実施して。
境界を越えないこと。完了後は要約だけ報告して。
```

```text
docs/claude-code-palette-all-screens.md の残り（他サブ画面＋メイン残滓＋再スキャン）を実施して。
完了後は要約だけ報告して。
```

### 共通ルール

- このファイルに書かれた範囲以外のリファクタ・機能追加はしない
- 既存のコーディングスタイル・命名・多言語（JA/EN/VI）方針に従う
- 不要なドキュメント追加・コミットはしない（明示指示がない限り）
- 色変更に付随する最小限以外のレイアウト／機能変更はしない

---

## 目的

osmPod の **全画面・全構成要素の色**を、osmGradus の固定パレットと **見た目として同じ**にする。

### 前回の失敗（繰り返さないこと）

「カラーテーマ固定＋osmGradus参考」では、メイン画面（scene + カード）だけ変わり、設定・ヘルプ・検索・プレイヤー等は未適用のまま残った。  
今回の完了条件は **メイン以外も含め、全 View がパレット準拠**であること。部分適用は不可。

例: 設定画面なら、osmGradus の設定画面と同じ色彩（背景 `#F2F2F7`、クリームのセクションカード、見出し・本文の固定文字色）。

---

## 絶対ルール

1. **色だけ**直す。レイアウト・文言・機能・ナビゲーション・ビジネスロジックは変えない。
2. ユーザー向けのテーマ切替は作らない／復活させない。色は固定。
3. 色の唯一のソースは `Services/AppPalette.swift`（すでに osmGradus `AppPalette.flatDefault` 準拠）。
4. 画面ごとに「どの面の上か」を判定し、対応トークンだけ使う。
5. SwiftUI の意味色・システム色を **面の色として使わない**（例外は下記「例外」節）。
6. 完了条件は「メイン以外も含め、全 View ファイルがパレット準拠」であること。

---

## 参照（必須・先に読む）

| 内容 | パス |
|------|------|
| パレット定義（正） | `/Users/osam/Developer/com.osamushikubo/osmGradus ALL/osm_gradus/lib/theme/app_colors.dart` |
| サブページ骨格 | `/Users/osam/Developer/com.osamushikubo/osmGradus ALL/osm_gradus/lib/widgets/osm_subpage_scaffold.dart` |
| サブページ Theme | `/Users/osam/Developer/com.osamushikubo/osmGradus ALL/osm_gradus/lib/theme/surface_theme.dart` |
| 設定セクション見た目 | `/Users/osam/Developer/com.osamushikubo/osmGradus ALL/osm_gradus/lib/widgets/settings_section.dart`（`SettingsSectionHeader` / `SettingsSectionCard` / `SettingsNoteText` / row 部品） |
| osmPod 既存パレット | `Services/AppPalette.swift` |
| osmPod 適用済み例 | `Views/Main/MainView.swift`, `GroupSectionView.swift`, `ShowRowView.swift` |

関連（過去 Step）: `docs/claude-code-steps.md` の Step 1 は「テーマ削除＋パレット導入」まで。本ファイルは **その後に残ったサブ画面などの色適用漏れ**を埋める。

---

## 面モデル（osmGradus と同じ）

| 面 | 背景 | 主文字 | 副文字 | 用途 |
|---|---|---|---|---|
| scene | `AppPalette.scene` (`#3D5993`) | `textOnScenePrimary` | `textOnSceneSecondary` | メインライブラリ背景上 |
| subpage | `subpageBackground` (`#F2F2F7`) | `textOnSubpagePrimary` | `textOnSubpageSecondary` | 設定・ヘルプ・データ管理・検索などのサブ画面全体 |
| card | `cardFill` (`#FFFAF2`) | `textOnCardPrimary` | `textOnCardSecondary` | サブ画面のセクションカード／メインのフォルダカード |
| accent | `accentColor` (`#007AFF`) | `onAccent` | — | ボタン・選択・tint |
| card chrome | `cardBorder` / `cardAccent` | — | — | 枠線・左ストライプ |

固定値（確認用）:

- scene `#3D5993`
- subpageBackground `#F2F2F7`
- cardFill `#FFFAF2`
- cardBorder `#F5C799`
- cardAccent `#FF9933`
- accentColor `#007AFF`
- onAccent `#FFFFFF`
- textOnScenePrimary `#FFFFFF` / Secondary `#B3FFFFFF`
- textOnSubpage/Card Primary `#1A1A1F` / Secondary `#61616B`

---

## 禁止（面の色として）

次を背景・文字・区切り・行背景に使わない。見つかったら `AppPalette` に置換:

- `.primary` / `.secondary` / `.tertiary`
- `.tint`（ルートの `.tint(AppPalette.accentColor)` 経由の暗黙依存は残してよいが、明示色は `AppPalette.accentColor` を使う方が望ましい）
- `Color.accentColor`（システム）→ `AppPalette.accentColor`
- `Color(.systemBackground)` / `systemGroupedBackground` / `secondarySystemGroupedBackground`
- `Color(.systemGray6)` / `systemFill` / `secondarySystemFill`
- `.regularMaterial` / `.thinMaterial` / `.bar` を **画面の主背景やセクション背景の代替**として使うこと  
  （トーストや一時オーバーレイのみ例外可。その場合も文字色はパレット）

### 例外（セマンティックで残してよい）

- 破壊的アクションの赤（`Color.red`）
- 警告オレンジ（プラン制限など、既存の意味色）
- 新着ドット緑 `Color(red: 0.67, green: 0.9, blue: 0.25)` や再生状態ドット（青/黄）など **状態インジケータ**
- スワイプ削除の赤／完了のグレー等、システム標準の destructive/complete アクション背景

---

## 実装方針（SwiftUI）

### A. サブページ共通ラッパーを作る（推奨）

osmGradus の `OsmSubpageScaffold` 相当を SwiftUI で追加する。例:

- 背景: `AppPalette.subpageBackground`
- ナビバー: 背景 `subpageBackground`、タイトル／戻る `textOnSubpagePrimary`
- List/Form: `.scrollContentBackground(.hidden)` + 背景を subpage に
- セクション行: 白系システム行背景をやめ、クリームのカード面にする

設定系は osmGradus `SettingsSectionCard` 相当が望ましい:

- 外側余白の上に角丸カード `cardFill`
- 見出しはカード外で `textOnSubpageSecondary`（小さめ）
- カード内テキストは `textOnCardPrimary` / Secondary
- 区切りは `cardBorder`
- Toggle / Slider / Progress のアクセントは `accentColor`

既存の `Form { Section { ... } }` を維持してよいが、**見た目が osmGradus 設定と揃うよう**背景・行背景・文字色を必ず上書きすること。Form のデフォルト見た目のまま残すのは不合格。

### B. 画面別の適用対象（漏れなく）

最低限、次をすべて監査・修正すること（`Views/` 配下の全 Swift）。

#### サブページ（subpage + card）— 今回の主戦場

- `SettingsView.swift` および同ファイル内の子画面（PlaybackOptions / Privacy 等）
- `HelpView.swift`
- `DataManagementView.swift` / `CloudSyncSettingsView.swift`
- `PlanManagementView.swift`
- `AddShowView.swift` / `PodcastSearchView.swift` / `PodcastDiscoveryAIView.swift`
- `PodcastShowPreviewSheet.swift` / `ShareImportSheet.swift`
- `EpisodeSearchView.swift` / `ShowEpisodePickerView.swift` / `AddEpisodeToGroupSheet.swift`
- `FolderEditView.swift`
- `PlayerView.swift`（シート／オーバーレイ含む）
- `CloudFilePreparationOverlay.swift`
- Share Extension 側 UI があれば同様

#### メイン（scene + card）— 残滓の掃除

- `MainView.swift` 内の `secondarySystemGroupedBackground` / `.secondary` / material 依存
- `LibrarySortMenu.swift` / `FolderDropBar.swift` / `ThumbnailArtworkView.swift`
- `EpisodeRowView.swift` の `isOnCard == false` 分岐がシステム色依存なら、実際の背景に合わせてパレット化

#### アプリ入口

- `App/osmPodApp.swift`: `.tint(AppPalette.accentColor)` は維持
- 可能なら全体を light 固定（ダークモードでシステム色が逆転してパレットと壊れるのを防ぐ）: `.preferredColorScheme(.light)`
- Privacy の fullScreenCover も subpage パレット適用

---

## 作業手順（この順で）

1. **現状調査**: `Views/` から `.primary|.secondary|.tertiary|systemGray|systemGrouped|systemFill|secondarySystem|regularMaterial|thinMaterial|Color\.accentColor|\.tint` を洗い出し、一覧化する。
2. **共通コンポーネント**（Subpage 背景修飾子 / Settings カード相当）を先に作る。
3. **`SettingsView` を osmGradus 設定画面と同じ色彩に仕上げる**（最初の完了サンプル）。
4. 同じパターンで他サブ画面へ横展開。
5. メイン画面の残滓を掃除。
6. **再スキャン**: 手順 1 の禁止パターンが「例外以外ゼロ」になるまで繰り返す。
7. 変更ファイル一覧と、画面ごとの before→after（どのトークンにしたか）を短く報告。

---

## 受け入れ基準（全部満たすこと）

- [ ] 設定画面の背景が `#F2F2F7`、セクションがクリームカード `#FFFAF2`、見出しが `#61616B`、本文が `#1A1A1F`
- [ ] ヘルプ・データ管理・検索・追加・プレイヤー・プラン等も同じ subpage/card 規則
- [ ] メインは scene `#3D5993` + カード `#FFFAF2` / 枠 `#F5C799` / ストライプ `#FF9933` のまま（壊さない）
- [ ] ダークモードやシステム外観に依存して色が変わらない
- [ ] `Views/` に禁止パターンの残存がない（セマンティック例外を除く）
- [ ] 機能・レイアウト差分は意図的な色変更に付随する最小限のみ

---

## やらないこと

- 新テーマエンジン、動的テーマ、アセット差し替え、アイコン刷新
- osmGradus の Flutter ウィジェットをそのまま移植する必要はない（見た目の規則を SwiftUI で再現すればよい）
- ドキュメント大量追加（必要なコメントは最小）

---

## 開始時の指示（Claude Code 向け）

まず調査結果（禁止パターンのヒット一覧）を出し、次に共通コンポーネント、次に `SettingsView` から実装せよ。人間が「このファイルを読んで実施」とだけ言った場合は、上記「作業手順」1〜7を最後まで実施する。
