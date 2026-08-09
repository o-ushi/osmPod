# App Store Privacy Checklist

対象: Apple App Review Guidelines 5.1.1(i), 5.1.2(i)

## 実装済み

- [x] PodcastDiscoveryAIViewの画面表示時にクリップボードを読まない
- [x] 「クリップボードを読み取る」の明示操作後だけURLを抽出
- [x] RSS通信前に取得目的、接続先URL、IPアドレス等が伝わる可能性を表示して確認
- [x] Google LLCへの送信を毎回確認
- [x] ユーザー入力話題、利用目的、履歴保存可能性、個人・センシティブ情報可能性を説明
- [x] 話題なしの場合は「定型promptのみで入力話題は送らない」と正確に区別
- [x] SettingsとHelpから3言語のPrivacy画面へ遷移
- [x] iTunes検索、RSS自動更新、音声/画像CDN、iCloud KVS全同期項目を説明
- [x] File Provider、共有Extension、JSON/ログ共有、保持・削除を説明
- [x] 外部ポリシーURLを `PrivacyPolicyLinks.externalPolicy` 定数へ分離
- [x] Factory ResetでSwiftDataレコード、EpisodeDownloads、LocalFileImports、FolderBookmarks、画像cache、Share一時データ、対象UserDefaultsを削除
- [x] Factory Reset時のiCloud KVS削除をユーザー選択式にした
- [x] ログ共有前に含有項目を確認
- [x] iPhone+iPad Universal（Targeted Device Family 1,2）を維持しつつ、`UIRequiresFullScreen`とiPad/iPhone双方の縦向き固定でiPhone相当のレイアウトに統一（2026-07-18、iPhone専用化はApple提出時に前バージョンのデバイス対応を外すため90101エラーで却下されたため復元）
- [x] 本体とShare Extensionのbuild番号を2へ更新

## App Store Connectで要確認

- [ ] App Privacy回答を実際の送信内容と一致させる
- [x] Privacy Policy URLを公開URLへ差し替え、`PrivacyPolicyLinks.externalPolicy`も更新（Google Docへ差し替え済み、2026-07-18／編集用`/edit`リンクだったため閲覧専用`/preview`へ差し替え、2026-08-09。Googleドキュメント側の「リンクを知っている全員」共有権限が「閲覧者」になっていることは別途要確認）
- [ ] Google、Apple、RSS/CDN、File Providerは第三者サービスとしてレビュー説明に記載
- [ ] iCloud同期が任意であることと、アプリ内削除経路（Settings → Data Management）をレビューNotesへ記載
- [ ] 診断ログはユーザー起動・共有先選択方式で、内容を共有前に表示することをレビューNotesへ記載
- [ ] スクリーンショットとメタデータがiPhone/iPad共通の縦向きレイアウトに一致することを確認

## 手動テスト手順

1. Podcast Discovery AIを開き、クリップボード許可表示もネットワーク通信も発生しないことを確認。
2. 複数RSS URLをコピーし「クリップボードを読み取る」を押す。URL一覧の通信確認でキャンセルし、HTTP通信が発生しないことを確認。
3. 同じ操作で「接続して取得」を押し、表示されたURLだけへ接続してプレビューされることを確認。
4. Google AIで話題あり/なしを各1回実行し、毎回確認が出て説明内容が異なることを確認。
5. SettingsとHelpの両方からPrivacy画面を開き、日本語/英語/ベトナム語を確認。
6. ダウンロード、ローカル取込、フォルダブックマーク、画像表示、Share取込待ち、設定変更を作成してFactory Reset。各ローカルデータが消えることを確認。
7. iCloud削除スイッチOFFでResetしクラウド値が残ること、ONでResetしKVS値が消えることを別のテストデータで確認。
8. 開発者メニューからログ共有を押し、含有項目の説明後にだけ共有シートが開くことを確認。
9. iPhone/iPad両方のシミュレータで縦向き固定とSplit View/Slide Overが無効なことを確認。Archive前のGeneral/Deployment InfoでiPhone+iPadが対応デバイスに含まれることを確認。
