# osmPod — iPad横の2画面と、再生の不具合3件

このファイルは、Claude Code に **iPad 横画面の左右分割** と **再生の不具合3件** を直させるための指示です。

## 使い方（人間 → Claude Code）

```text
docs/claude-code-ipad-split-and-playback-bugs.md を読んで、書いてある通りに実施して。
完了後は実施内容の要約だけ報告して。各不具合は原因と、どう直したかを1〜2文で。
```

まとめて難しい場合は、この順で区切る。

```text
docs/claude-code-ipad-split-and-playback-bugs.md の「作業A」だけ実施して。
境界を越えないこと。完了後は要約だけ報告して。
```

```text
docs/claude-code-ipad-split-and-playback-bugs.md の「作業B」だけ実施して。
境界を越えないこと。完了後は要約だけ報告して。
```

```text
docs/claude-code-ipad-split-and-playback-bugs.md の「作業C」だけ実施して。
境界を越えないこと。完了後は要約だけ報告して。
```

```text
docs/claude-code-ipad-split-and-playback-bugs.md の「作業D」だけ実施して。
境界を越えないこと。完了後は要約だけ報告して。
```

### 共通ルール

- このファイルに書いた範囲以外のリファクタ・機能追加・文言の改稿はしない
- 既存のコーディングスタイル・命名・多言語（JA/EN/VI）方針に従う
- コミットはしない
- iPhone の見た目と操作は変えない。iPhone は縦向きのまま
- ビルドが通る状態で終える
- 推測で別の再生仕様を足さない。各作業の「こう動く」が仕様

---

## 作業A — iPadを横にしたとき、左がライブラリ、右が再生

### こう動く

iPad を横にしたときだけ、画面を左右に分ける。

```text
┌────────────────────────────┬──────────────────┐
│ 検索                        │ アートワーク      │
│ フォルダ                    │ タイトル / 番組    │
│   番組                      │ シーク・再生      │
│     エピソード（タップで再生）│ 概要・DL・お気に入り│
└────────────────────────────┴──────────────────┘
```

- 左がライブラリ、右が再生。割合は左6・右4。右は幅 400pt 前後の固定でもよい。右を半分より広くしない（アートは正方形で、広いと余白が寂しくなる）
- 左のエピソードをタップすると、その場で再生が始まり、右の表示が切り替わる
- 何も再生していないときは、右は空の案内（「エピソードを選ぶとここに出る」相当。JA/EN/VI）にする
- 設定・番組追加・ヘルプ・フォルダ編集などは、今どおりシートのまま。左右のペインを取らない
- 右に再生があるあいだ、左の下のミニプレーヤーは出さない。操作が二つに分かれないようにする
- 再生画面用のシート（`MainView` の `isPresentingPlayer` → `PlayerView()`）は、この横分割のときは出さない
- iPad の縦向きは、今の1カラム（iPhone相当）のまま
- iPhone は縦固定のまま。レイアウトも変えない

### 現状の手がかり

- 向きはソースの `Info.plist` には無い。`GENERATE_INFOPLIST_FILE = YES` と `INFOPLIST_FILE = Info.plist` の併存で、Xcode がビルド時にマージする。向きの実体はアプリターゲットのビルド設定  
  `osmPod.xcodeproj/project.pbxproj` の Debug（`A80000010000000000000003`）と Release（`A80000010000000000000004`）
- 今の値は両方とも次のとおり。`TARGETED_DEVICE_FAMILY = "1,2"`（iPhone+iPad）
  - `INFOPLIST_KEY_UIRequiresFullScreen = YES`
  - `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait`
  - `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = UIInterfaceOrientationPortrait`
- ソースの `Info.plist` は URL スキーム、バックグラウンド再生、iCloud の説明だけ。共有拡張 `osmPodShare/Info.plist` に向きのキーは無い
- 過去の申請では、iPad 対応を外して iPhone 専用にすると **90101**（前バージョンが対応していたデバイスを外した）で却下されている。デバイスファミリーは変えない
- ライブラリは `Views/Main/MainView.swift`。再生の本体は `Views/Main/PlayerView.swift` の `PlayerView`。下のバーは `MiniPlayerView`
- iPad は縦でも横でも size class が regular / regular になる。`horizontalSizeClass == .regular` だけでは横画面を判定できない。iPad かつ幅 > 高さ、で判定する

### 申請で落ちない向きの書き方

Archive は Release を見る。Debug だけ変えると、シミュレータでは横になり、提出バイナリは縦のままになる。アプリターゲットの Debug と Release の両方を、同じ内容にする。

iPad の値は、スペース区切りの1文字列で書く。配列の書き方を崩すと、生成物の `UISupportedInterfaceOrientations~ipad` が配列にならず、アップロード時に Info.plist 不正で落ちる。

```text
INFOPLIST_KEY_UIRequiresFullScreen = YES;
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = UIInterfaceOrientationPortrait;
INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
TARGETED_DEVICE_FAMILY = "1,2";
```

ビルド後のアプリ本体 `Info.plist` は、こうなっていること。

```xml
<key>UIRequiresFullScreen</key>
<true/>
<key>UISupportedInterfaceOrientations</key>
<array>
	<string>UIInterfaceOrientationPortrait</string>
</array>
<key>UISupportedInterfaceOrientations~ipad</key>
<array>
	<string>UIInterfaceOrientationPortrait</string>
	<string>UIInterfaceOrientationPortraitUpsideDown</string>
	<string>UIInterfaceOrientationLandscapeLeft</string>
	<string>UIInterfaceOrientationLandscapeRight</string>
</array>
```

守ること:

- `UIRequiresFullScreen` は YES のまま。iPad が4方向すべてを持たない状態でこれを外すと、**ITMS-90474**（iPad Multitasking には Portrait / PortraitUpsideDown / LandscapeLeft / LandscapeRight が必要）で提出できない。フルスクリーン必須のままで、縦・上下逆さま・横左・横右の4つにする（上下逆さまが無いと、横から iPad を逆さにしたとき横表示のまま残る）
- 横向きは `_iPad` だけに足す。`_iPhone` と、接尾辞なしの `UISupportedInterfaceOrientations` に横を入れない
- ソースの `Info.plist` と `osmPodShare/Info.plist` に向きのキーを足さない。ビルド設定と二重になると、マージ後の plist が壊れる
- `TARGETED_DEVICE_FAMILY` は `"1,2"` のまま。共有拡張も触らない
- 実装後、Release 設定でビルドした `.app` の Info.plist を `plutil -p` で見て、上の3キーが配列と真偽値になっていることを確認する。リポジトリの `Info.plist` だけを見て終わらない

### やること

1. 上の「申請で落ちない向きの書き方」どおりに、アプリターゲットの Debug と Release を変える
2. iPad 横のときだけ上記の2ペインにする。右は今の `PlayerView` の中身をシートではなく常時表示する
3. 左は今のライブラリ（検索、フォルダ、番組、エピソード）のまま使えるようにする
4. `docs/app-store-privacy-checklist.md` の「iPad も縦向き固定」という記述と、手動テスト手順9だけ、今回の仕様に合わせて直す。iPhone は縦固定、iPad は縦＋上下逆さま＋横左＋横右、`UIRequiresFullScreen` は YES のまま（Split View / Slide Over は無効）、`TARGETED_DEVICE_FAMILY` は 1,2 のまま。メタデータ本文やスクリーンショット用の文案は触らない

### 確認

- iPhone シミュレータ: 縦のまま。横にならない。見た目が以前と同じ
- iPad シミュレータ縦: 今までどおり1カラム。ミニプレーヤーから再生シートが開く
- iPad シミュレータ横: 左ライブラリ / 右再生。エピソードタップで右が切り替わる。未再生時は右が空案内。設定や番組追加はシート。ミニプレーヤーは出ない。上下逆さまにすると縦の1カラムになる
- 横から縦へ戻すと、再生は途切れず、1カラムに戻る
- Release ビルドの `.app/Info.plist` で、`UIRequiresFullScreen` が true、iPhone 向きが縦のみ、`UISupportedInterfaceOrientations~ipad` が縦・上下逆さま・横左・横右の配列であること

---

## 作業B — 終わり際に、最後の十数秒が1回だけもう一度鳴る

### 症状（ユーザー報告）

たまに、勝手に少し戻って同じ箇所を再生する。終わりぎわに多い。outro の「ありがとうございました」のあたりで次のエピソードに移ると思ったら、同じエピソードの最後の十数秒（体感では約10秒）がもう一度鳴る。繰り返しは1回だけ。

### こう動く

エピソードの終わりは1回だけ。末尾を巻き戻して再生し直さない。終わったら、作業Cのルールで次へ進むか、次が無ければ止まる。

途中の通信切れからの復帰は残す。直してよいのは「終わり付近で、同じ末尾をもう一度鳴らす」動きだけ。

### 調査する箇所（`Services/AudioPlayerService.swift`）

当たりは次の競合。実装時にログと処理順で確かめてから直す。

- `startPeriodicSave` は 10 秒ごとに `persistPosition` する。保存位置は再生ヘッドより最大約10秒古い
- 終わり付近で `AVPlayerItem.playbackStalledNotification` や待ちウォッチドッグが `handlePlaybackStall` → `reloadCurrentStreamPreservingState` を呼び、古い位置へ seek して末尾をもう一度再生する。その後 `AVPlayerItemDidPlayToEndTime` → `onPlaybackEnded` で次へ進む、という1回だけの繰り返しと一致する
- `onPlaybackEnded` は位置を 0 にして `didReachPlaybackEnd = true` にしたあと `enqueueNextEpisode` する。これと stall / item `.failed` / `pendingReloadResumeAt` の復帰が競合すると、終わり直前の位置へ戻ることがある
- フォアグラウンド復帰の `handleReturnedToForegroundDebounced` にも「古い位置で currentTime を上書きすると勝手に戻る」という既存コメントがある。終わり際の再再生がこの経路なら、ここも直す

### 直し方の条件

- 残り時間が短い、またはすでに末尾へ到達した item を、stall や失敗復帰の理由で巻き戻して再生し直さない。終わりとして1回だけ処理する
- 同じ `playbackGeneration` で `onPlaybackEnded` は1回だけ効くようにする。終わり処理のあとから届いた stall リロードや、古い `playbackPosition` への seek で再生を再開しない
- 通信復帰で途中から聴き直す動作は、終わり以外では維持する

### 確認

- エピソードの終了十数秒前から聴き、末尾が1回だけ鳴って次へ進む（または停止する）こと。同じ outro がもう一度鳴らないこと
- 途中で一時的に読めないストリームが、終わり以外では従来どおり位置を保って復帰すること

---

## 作業C — ランダム再生オフなのに、別の番組へ飛ぶ

### 症状（ユーザー報告）

ヘッダーのランダム再生をオフにしているのに、同じ番組の次のエピソードではなく、別の番組に飛ぶことがある。毎回ではない。

### こう動く

ヘッダーのランダム再生（`isRandomModeEnabled` / `AppSettings.randomModeEnabled`）がオフのとき:

- 自然終了も、次へボタン（`skipToNextEpisode`）も、**今の番組の次のエピソード**へ進む
- 「次」はライブラリのエピソード並び（`episodeOrderOption` と昇順／降順）で、今のエピソードの隣。`publishedAt` が nil でも並びで決める
- 別の番組には飛ばない
- その番組に次が無いときだけ、設定「別のエピソードを自動再生する」（`AppSettings.autoPlayEnabled`）がオンなら、その設定の選び方（`AutoPlayOrder`）に任せる。オフならそこで停止する
- 再生済みを飛ばす設定（`skipPlayedEpisodes`）は、同じ番組の中で従来どおり適用する

ランダム再生がオンのときは、今の横断ランダム（`randomModeNextEpisode`）のまま。

設定の「別のエピソードを自動再生する」自体は消さない。ランダムがオフの通常の次送りが、この設定を待たずに別番組へ落ちるのが不具合。

### 現状の手がかり（`Services/AudioPlayerService.swift`）

`enqueueNextEpisode` は次の順。

1. `isRandomModeEnabled` なら `randomModeNextEpisode`（全番組から未再生をランダム）
2. 否则 `nextEpisodeToAutoPlay`
3. それが nil なら `globalAutoPlayNextEpisode`

毎回ではない理由は、2 が成功すると同じ並びに残り、2 が nil のときだけ 3 に落ちるため。3 は別番組を候補に含み、未再生の新着は「他番組の新着」が「同じ番組の続き」より前に来る。`AutoPlayOrder.random` はこの中だけでランダムになる。

2 が nil になる条件:

- `queueContext == .none`（検索、復元、次送りのグローバル経路、`teardownPlayer` がいったん `.none` にすることと組み合わさる経路）
- `episode.publishedAt == nil` で即 return
- フォルダ文脈（`.folder`）のとき、次が別番組のエピソードになり得る。ランダムオフの「次」はフォルダ混在ではなく、同じ番組の隣にする

`skipToNextEpisode` も同じ優先順位なので、ボタンでも直す。

### 確認

- ランダムオフ、自動再生オフ。同じ番組のエピソードが続くとき、終了後も次へボタンも同じ番組の隣へ進む。別番組に飛ばない
- `publishedAt` が無いエピソードでも、一覧の隣へ進む
- 番組の最後のエピソードで、自動再生オフなら停止する。自動再生オンなら設定の選び方に従う（このときだけ別番組があってよい）
- ランダムオンのときは、これまでどおり別番組を含むランダムのまま
- フォルダに複数番組が入っていても、ランダムオフの次は再生中の番組の中で進む

---

## 作業D — 15秒戻るが、表示も再生位置も戻らない

### 症状（ユーザー報告）

⏪（15秒戻る）を押しても、時間が戻らない。

### こう動く

再生画面、ミニプレーヤー、ロック画面／コントロールセンターの15秒戻るで、再生位置が約15秒戻る。表示の時刻とスライダーも戻り、再生中なら戻った位置から音が続く。15秒進む、スライダーの seek も、同じ経路なので一緒に壊れないようにする。

### 現状の手がかり

- ボタンは `Views/Main/PlayerView.swift` の `PlayerView` と `MiniPlayerView`。どちらも `audioPlayer.seekBackward()`（既定15秒）
- リモートは `Services/NowPlayingSyncCoordinator.swift` の `skipBackwardCommand`。同じ `seekBackward()`
- 実装は `AudioPlayerService.applySeek`
  - `isSeeking = true` にして `currentTime` を目標に書き、`player.seek` の完了で `isSeeking = false`
  - 周期オブザーバー（1秒）は MainActor の `Task` に乗せて、`isSeeking` でなければ `currentTime` を上書きする
- seek より前に採取された時刻が、seek 完了で `isSeeking` が降りたあとに届くと、表示が元の時刻へ戻る。押しても戻らない、に見える
- `player` がまだ無いときに seek しても完了コールバックが来ない。`isSeeking` が true のまま残ると、その後の時刻更新が止まる

### 直し方の条件

- seek 対象の時刻を世代か目標値として覚え、その seek より前の周期サンプルでは `currentTime` を上書きしない
- 戻ったとみなすのは、AVPlayer の実時刻が目標付近になったとき。表示だけ先に戻して、次のサンプルで戻さない
- 進む・スライダー・リモートの skip も同じ `applySeek` で直す
- `player` が nil のときは、保存する再生位置（`playbackPosition`）を目標に更新し、`isSeeking` を残さない。あとから再生を始めたとき、その位置から鳴る

### 確認

- 再生中に15秒戻るを数回押し、表示と音が毎回約15秒戻ること。直後に元の時刻へ跳ね返らないこと
- 15秒進む、スライダー、一時停止中の戻る、も同様
- ロック画面の15秒戻るも、アプリに戻ったときの位置と一致すること

---

## 触ってよい範囲の目安

- 作業A: アプリターゲットの Debug / Release の向きビルド設定、`MainView` / `PlayerView` の分割、空案内の文言、`docs/app-store-privacy-checklist.md` の該当箇条。ソースの `Info.plist` と共有拡張の plist は向きを足さない
- 作業B・C・D: `Services/AudioPlayerService.swift` を中心に、リモート seek が同じ不具合なら `Services/NowPlayingSyncCoordinator.swift`。作業Cで並び順の関数がライブラリ側にあるなら、その参照だけ

再生オプションの設定項目の追加・削除はしない。
