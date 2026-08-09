# osmPod — Claude Code 向けステップ作業指示書

このファイルは、Claude Code に **ステップ単位で作業させるためのプロンプト集** です。

## 使い方（人間 → Claude Code）

Claude Code に、次のように指示してください。

```text
docs/claude-code-steps.md の Step 1 だけ実施して。
Step の境界を越えないこと。完了後は実施内容の要約だけ報告して。
```

```text
docs/claude-code-steps.md の Step 2 だけ実施して。
Step の境界を越えないこと。完了後は実施内容の要約だけ報告して。
```

```text
docs/claude-code-steps.md の Step 3 だけ実施して。
コード変更はしない。レビュー結果だけ報告して。
```

### 共通ルール（全 Step 共通）

- 指定された Step 以外の変更・調査・リファクタはしない
- 既存のコーディングスタイル・命名・多言語（JA/EN/VI）方針に従う
- 不要なドキュメント追加・コミットはしない（明示指示がない限り）
- ビルドが通る状態で Step を終える（Step 3 はレビューのみのため除く）
- 参照プロジェクトのパス:
  - osmGradus: `/Users/osam/Developer/com.osamushikubo/osmGradus ALL/osm_gradus/`
  - osmWashabe: `/Users/osam/Developer/com.osamushikubo/osmWashabe ALL/osmWashabe/`

---

## Step 1 — カラーテーマと見た目の削除（osmGradus 準拠の固定色へ）

### 目的

ユーザー向けの「カラーテーマ」「見た目」設定は結局使わないので削除する。  
見た目の色合いは **osmGradus の固定パレット** に倣う。

### 参照（色の正）

`/Users/osam/Developer/com.osamushikubo/osmGradus ALL/osm_gradus/lib/theme/app_colors.dart` の `AppPalette.flatDefault`:

| 役割 | 色 |
|------|-----|
| scene（メイン背景） | `#3D5993` |
| subpageBackground | `#F2F2F7` |
| cardFill | `#FFFAF2` |
| cardBorder | `#F5C799` |
| cardAccent | `#FF9933` |
| accentColor | `#007AFF` |
| onAccent | `#FFFFFF` |
| textOnScenePrimary / Secondary | `#FFFFFF` / `#B3FFFFFF` |
| textOnSubpage / textOnCard Primary / Secondary | `#1A1A1F` / `#61616B` |

方針コメント（Gradus）: 「osmファミリー共通の固定カラーパレット。ユーザー向けのテーマ／外観切り替えは持たない。」

### 現状（削除・置換対象の手がかり）

- `Services/ColorThemeManager.swift` — `ColorTheme` / `ColorThemeManager`
- `Services/AppAppearanceStore.swift` — `AppRowStyle` / `AppSceneTint` / `AppAppearanceStore`
- `Views/Main/AppearanceSettingsView.swift` — 見た目設定 UI
- `Views/Main/SettingsView.swift` — 「カラーテーマ」Section / 「見た目」NavigationLink
- `App/osmPodApp.swift` — `ColorThemeManager` / `AppAppearanceStore` の生成・`.environment`・`.tint`
- `Views/Main/MainView.swift` / `GroupSectionView.swift` など — `appearanceStore` / `colorThemeManager` 参照
- `Services/LocalizedStrings.swift` — テーマ／見た目関連文言（使われなくなったら削除）

### やること

1. 設定画面から **カラーテーマ選択** と **見た目（Appearance）** を削除する
2. `ColorThemeManager` / `AppAppearanceStore` / `AppearanceSettingsView` およびそれに紐づく UserDefaults キー・enum・文言を、参照がなくなる形で削除する（または固定パレット1本に置き換えて参照を単純化する）
3. アプリ全体のアクセント・シーン背景・カード見た目を、上記 osmGradus パレットに固定する
4. ダークモード時の特殊分岐が「テーマ選択前提」で複雑なら、Gradus 方針に合わせて単純化する（ユーザーが選べる見た目は残さない）
5. ヘルプ／設定の説明文にテーマ・見た目の言及が残っていれば整合させる（文言の大幅改稿は Step 3 に回さず、削除に伴う最低限の整合のみ）

### やらないこと

- 開発者モードやログの追加・改修（→ Step 2）
- 全体レビューや無関係なリファクタ（→ Step 3）
- Now Playing / CC / LS の再生同期ロジック変更

### 完了条件

- 設定にカラーテーマ・見た目 UI が無い
- ビルドが通る
- メイン画面・設定・カード等が Gradus 系の固定色で破綻なく見える
- テーマ／見た目用の死んだコード・死んだ文言が実質残っていない

### 報告してほしいこと

- 削除したファイル／主な変更ファイル
- 固定色をどこに集約したか（新規 `AppPalette` 相当など）
- 残課題があれば1〜3行

---

## Step 2 — 開発者モード整備＆ Now Playing 表示ズレ調査用ログ強化

### 目的

Control Center（CS）／ロック画面（LS）の ▶︎／⏸ 表示が、実際の再生状態とズレる不具合が潰しきれていない。  
**現象を捕まえたときに、ログだけで原因候補を特定できる** 粒度の情報を取る。

### 既知の再現パターン（調査対象）

**パターン1 — CS だけ ⏸**
- 実際は停止中なのに、CS だけ ⏸
- タップすると一瞬 ▶︎ になるがすぐ ⏸ に戻る
- アプリ内デッキは正常。再生・停止を繰り返すと CS も復帰

**パターン2 — LS の表示ズレ**
- 実際は再生中なのに、LS が ▶︎
- タップすると実際の演奏が止まり、LS は ▶︎ のまま（この時点でズレ解消）

### 現状（先に読むこと — 二重実装禁止）

osmPod には **すでに** 次がある。ゼロから作り直さない。足りないところを足す／強化する。

- 設定下端 40pt を 7 回タップで開発者モード ON/OFF（`Views/Main/SettingsView.swift` の `registerDevAreaTap`）
- `AppSettings.developerModeEnabled`
- 開発者向け「ログ共有」＋ `Services/DebugLogExporter.swift`（`OSLogStore`、subsystem `com.osamushikubo.osmPod`）
- `AudioPlayerService` の `bgLog`（category `BGAudio`）と Now Playing 再同期（`applyNowPlayingInfo` / `scheduleNowPlayingReassert` / `forceNowPlayingRateEdge` 等）

UX の参考（必要なら）:
- osmWashabe: `lib/views/settings/settings_view.dart` の `_onDevAreaTap`（7 タップ）
- osmGradus: 同様の 7 タップ＋ログ（Gradus 側コメントで osmPod `DebugLogExporter` を意識している）

### やること

#### A. 開発者モード UX

1. 既存の 7 タップ切替が壊れていないことを確認し、必要なら Washabe 相当に揃える（重複 UI は作らない）
2. 開発者モード ON 時に、ログ共有導線が分かりやすく使えることを確認／必要最小限の改善
3. ログ共有前のプライバシー開示（既存アラート）を維持

#### B. 「在りたくない姿」を避けるためのログ設計（最重要）

現象を捕まえても原因が分からないログは失敗。最低でも、1 イベントごとに次を **1 行にまとめて**（または隣接行で）出せること。

必須フィールド例（名前は既存スタイルに合わせてよい）:

| フィールド | 意味 |
|-----------|------|
| `event` | 何が起きたか（例: `pausePlayback`, `resumePlayback`, `remote.play`, `remote.pause`, `applyNowPlaying`, `reassert`, `rateEdge`, `timeControl`, `player.rate`, `app.foreground`, `app.background`, `routeChange`, `interruption`） |
| `truth.isPlaying` | アプリ正の再生状態 |
| `av.rate` | `AVPlayer.rate` |
| `av.timeControl` | `timeControlStatus`（playing/paused/waiting + reason） |
| `np.rate` | `MPNowPlayingInfoCenter` に書いた／読んだ PlaybackRate |
| `np.elapsed` | 書いた／読んだ elapsed |
| `np.hasInfo` | nowPlayingInfo が nil かどうか |
| `remote.playEnabled` / `pauseEnabled` | RemoteCommand の有効状態 |
| `expectedPlaying` | reassert 中に期待している状態 |
| `scene` | foreground / background / inactive |
| `episodeID` | 短く識別できる ID（プライバシーに配慮しタイトル全文は避けるか必要最小限） |
| `trigger` | 呼び出し元（アプリ内ボタン / remote / observer / timer / reassert） |

特に重要なタイミング（漏らさない）:

1. アプリ内 play / pause の入口と出口（正を変える直前・直後、Now Playing 書き込み直後）
2. `MPRemoteCommandCenter` の play / pause 受信時（CS/LS タップ）— 受信前後の truth / av / np
3. `applyNowPlayingInfo` / `scheduleNowPlayingReassert` / `forceNowPlayingRateEdge` の各実行（期待状態と実際に書いた rate）
4. `timeControlStatus` / `player.rate` の observer 発火（正と実再生の不一致を明示）
5. foreground / background / resignActive / becomeActive
6. audio session interruption / route change
7. reassert ループが **打ち切られた理由**（`isPlaying != expectedPlaying` 等）
8. 「正は paused なのに av.rate>0」「正は playing なのに np.rate=0」のような **不一致を WARNING で明示**

#### C. ログ回収

- `DebugLogExporter` が上記カテゴリを確実に拾えること（subsystem 統一）
- 必要なら category を `NowPlaying` 等に分けてもよいが、エクスポート対象から漏れないこと
- 共有テキストの先頭に短いヘッダ（アプバージョン、OS、開発者モード ON 時刻、直近何時間分）を付けるとよい
- ログが冗長すぎて読めない場合は、通常は要約行＋不一致時のみ詳細、でもよい（ただし上記必須フィールドは残す）

#### D. 動作確認観点（コード上で担保できる範囲）

- 開発者モード OFF では、過剰ログでリリース品質を落とさない（可能なら `developerModeEnabled` または適切な log level で間引く。ただし **再現調査に必要な不一致 WARNING は残してよい** — 判断して明記）
- 既存の再生・停止・CC 操作を壊さない（ロジック改修はログと、ログのために必要な最小限のフックに留める）
- **表示ズレ自体の修正は本 Step の主目的ではない**（原因がログから一意に分かるなら、最小限の修正案をコメントまたは短いメモで残すのは可。大きな挙動変更はしない）

### やらないこと

- カラーテーマ／見た目の削除（→ Step 1。未実施なら触らない）
- 全体レビュー（→ Step 3）
- 「たぶん直った」系の大きな Now Playing 書き直し（本 Step はまず観測可能性）

### 完了条件

- 7 タップ開発者モード＋ログ共有が使える
- CS/LS ズレの両パターンを想定したとき、ログに「誰が・いつ・正/AV/NP のどれがズレたか」が残る
- ビルドが通る

### 報告してほしいこと

- 追加／変更したログポイント一覧（event 名）
- 開発者モード OFF 時のログ方針
- 再現時に見るべきログの読み方（5〜10 行程度のチートシート）

---

## Step 3 — 全体レビュー（世界トップレベル視点・コード変更なし）

### 目的

実装変更は行わず、コードベースをレビューして報告する。  
Step 1 / Step 2 実施後の状態を前提に見てよい（未実施なら現状のままレビュー）。

### レビュー視点

1. **重複している機能** — 同じことを複数経路・複数型・複数 UI でやっていないか
2. **ゾンビ化している機能** — 到達不能、設定だけ残存、参照ゼロ、旧実装の残骸、`#if DEBUG` と隠しメニューの混乱など
3. **動線が冗長的な機能** — ユーザーが同じ目的に何タップも要する、設定が分散、似た画面が並ぶ
4. **ヘルプ／プライバシーポリシー等の文言と実機能の整合性**
   - `Views/Main/HelpView.swift`
   - `Services/LocalizedStrings.swift`
   - `Views/Main/SettingsView.swift` 内の Privacy 関連
   - `docs/privacy-policy-ja.md`
   - 外部ポリシーリンク（`info` にある場合）
5. **その他** — 保守性、危険な状態管理、Now Playing 周辺の構造的リスク、多言語抜け、Store / プラン周り、Share Extension、iCloud など

### やること

1. 上記 1️⃣〜5️⃣ の観点でリポジトリを調査する
2. 指摘は **重大度**（Critical / High / Medium / Low）と、可能なら **ファイルパス** を付ける
3. 各指摘に「なぜ問題か」「推奨アクション（修正方針）」を短く付ける
4. 良い点も簡潔に 3〜5 個挙げ、レビューの信頼性を担保する
5. 最後に「今スプリントでやるならこの順」で優先度トップ 5 を出す

### やらないこと

- コード・文言・ドキュメントの変更
- Step 1 / 2 の追加実装
- 大規模リファクタの実施

### 完了条件

- 5️⃣視点をカバーしたレビュー報告が提出されている
- 変更差分が無い（またはユーザーが許可したメモファイル以外無い）

### 報告フォーマット（厳守）

```markdown
# osmPod 全体レビュー

## 総評
（3〜6 行）

## 1️⃣ 重複している機能
- [重大度] 内容 / 根拠パス / 推奨

## 2️⃣ ゾンビ化している機能
- ...

## 3️⃣ 動線が冗長的な機能
- ...

## 4️⃣ 文言と実機能の整合性
- ...

## 5️⃣ その他
- ...

## 良い点
- ...

## 今やるならこの順（Top 5）
1. ...
```

---

## 推奨実施順

1. Step 1（見た目の固定化・削除）
2. Step 2（観測ログ強化）
3. Step 3（レビュー）
4. （別タスク）Step 2 のログで捕まえた証拠をもとに、CS/LS 表示ズレを本修正

Step 4（本修正）はこのファイルの範囲外。ログが揃ってから別指示で行う。
