import SwiftUI

/// osmファミリー共通の固定カラーパレット（osmGradus `AppPalette.flatDefault` 準拠）。
/// ユーザー向けのテーマ／外観切り替えは持たない。
enum AppPalette {
    /// メイン画面（ライブラリ）の背景色。
    static let scene = Color(red: 0x3D / 255, green: 0x59 / 255, blue: 0x93 / 255)

    /// 設定・ヘルプなどサブ画面の背景色。
    static let subpageBackground = Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF7 / 255)

    /// シーン上に浮かぶカード（フォルダ行等）の塗り色。
    static let cardFill = Color(red: 0xFF / 255, green: 0xFA / 255, blue: 0xF2 / 255)

    /// カードの枠線色。
    static let cardBorder = Color(red: 0xF5 / 255, green: 0xC7 / 255, blue: 0x99 / 255)

    /// カードのアクセントストライプ色。
    static let cardAccent = Color(red: 0xFF / 255, green: 0x99 / 255, blue: 0x33 / 255)

    /// ボタン等のメインアクセントカラー。
    static let accentColor = Color(red: 0x00 / 255, green: 0x7A / 255, blue: 0xFF / 255)

    /// [accentColor] の上に乗せる文字・アイコン色。
    static let onAccent = Color.white

    /// [scene] の上に直接乗せる文字色。
    static let textOnScenePrimary = Color.white
    static let textOnSceneSecondary = Color.white.opacity(0xB3 / 255)

    /// [subpageBackground] / [cardFill] の上に乗せる文字色。
    static let textOnSubpagePrimary = Color(red: 0x1A / 255, green: 0x1A / 255, blue: 0x1F / 255)
    static let textOnSubpageSecondary = Color(red: 0x61 / 255, green: 0x61 / 255, blue: 0x6B / 255)
    static let textOnCardPrimary = textOnSubpagePrimary
    static let textOnCardSecondary = textOnSubpageSecondary

    /// フォルダ行カード（旧 `AppRowStyle.clean` 相当）の固定枠線幅。
    static let cardBorderWidth: CGFloat = 1.0
}

extension View {
    /// osmGradus サブページ相当。Form/List のシステム背景を消し、固定パレット＋ライト固定にする。
    func osmSubpageListChrome() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AppPalette.subpageBackground)
            .tint(AppPalette.accentColor)
            .preferredColorScheme(.light)
            .toolbarBackground(AppPalette.subpageBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
    }

    /// 設定セクション行をクリームカード面にする。
    func osmSettingsCardRow() -> some View {
        self
            .listRowBackground(AppPalette.cardFill)
            .listRowSeparatorTint(AppPalette.cardBorder)
            .foregroundStyle(AppPalette.textOnCardPrimary)
    }
}
