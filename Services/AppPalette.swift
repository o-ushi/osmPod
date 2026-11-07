import ObjectiveC
import SwiftUI
import UIKit

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
    /// 青シーン上の時刻・バッテリを白にする。
    /// `toolbarColorScheme` は iOS 27 のステータスバーに届かないため、UIKit の preferredStatusBarStyle を上書きする。
    func osmSceneStatusBar() -> some View {
        self
            .background(SceneStatusBarForcer())
            .toolbarBackground(AppPalette.scene, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }

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

/// ライト固定のまま、青背景のステータスバーだけ白文字にする。
/// SwiftUI の `toolbarColorScheme` は iOS 27 では時刻・バッテリに効かない。
private struct SceneStatusBarForcer: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SceneStatusBarController {
        SceneStatusBarController()
    }

    func updateUIViewController(_ controller: SceneStatusBarController, context: Context) {
        controller.refresh()
    }
}

private final class SceneStatusBarController: UIViewController {
    private var presentationObservation: NSKeyValueObservation?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refresh()
        observePresentationsIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        refresh()
    }

    func refresh() {
        SceneStatusBarStyle.applyForCurrentPresentation()
    }

    private func observePresentationsIfNeeded() {
        guard presentationObservation == nil, let root = SceneStatusBarStyle.rootViewController else { return }
        presentationObservation = root.observe(\.presentedViewController, options: [.new]) { _, _ in
            DispatchQueue.main.async {
                SceneStatusBarStyle.applyForCurrentPresentation()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                SceneStatusBarStyle.applyForCurrentPresentation()
            }
        }
    }
}

private enum SceneStatusBarStyle {
    private nonisolated(unsafe) static var styleKey: UInt8 = 0
    private nonisolated(unsafe) static var patchedOwners = Set<ObjectIdentifier>()
    private nonisolated(unsafe) static var lastLeafID: ObjectIdentifier?
    private nonisolated(unsafe) static var lastStyle: Int?
    private nonisolated(unsafe) static var isWatchingPresentation = false

    @MainActor
    static var rootViewController: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first
        return window?.rootViewController
    }

    @MainActor
    static func applyForCurrentPresentation() {
        guard let root = rootViewController else { return }
        let style: UIStatusBarStyle = coversStatusBar(from: root) ? .darkContent : .lightContent
        var seen = Set<ObjectIdentifier>()
        var current: UIViewController? = root
        var leaf = root
        while let controller = current, seen.insert(ObjectIdentifier(controller)).inserted {
            install(on: controller)
            objc_setAssociatedObject(
                controller,
                &styleKey,
                NSNumber(value: style.rawValue),
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
            leaf = controller
            current = controller.childForStatusBarStyle
        }
        watchPresentationUntilDismissed(from: root)
        let leafID = ObjectIdentifier(leaf)
        guard lastLeafID != leafID || lastStyle != style.rawValue else { return }
        lastLeafID = leafID
        lastStyle = style.rawValue
        root.setNeedsStatusBarAppearanceUpdate()
    }

    /// 全画面モーダルを閉じても `presentedViewController` の KVO やレイアウト更新は来ないことがあり、
    /// 文字色が黒のまま残る。モーダルが開いている間だけ、閉じたことを定期的に確かめる。
    @MainActor
    private static func watchPresentationUntilDismissed(from root: UIViewController) {
        guard root.presentedViewController != nil, !isWatchingPresentation else { return }
        isWatchingPresentation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isWatchingPresentation = false
            applyForCurrentPresentation()
        }
    }

    @MainActor
    private static func coversStatusBar(from root: UIViewController) -> Bool {
        var presented = root.presentedViewController
        while let next = presented?.presentedViewController {
            presented = next
        }
        guard let presented, let window = root.view.window ?? presented.view.window else { return false }
        let frame = presented.view.convert(presented.view.bounds, to: window)
        guard frame.height > 20 else { return false }
        let barHeight = window.windowScene?.statusBarManager?.statusBarFrame.height ?? 54
        return frame.minY <= barHeight + 8
    }

    private static func install(on controller: UIViewController) {
        let selector = #selector(getter: UIViewController.preferredStatusBarStyle)
        var owner: AnyClass? = type(of: controller)
        while let current = owner, !classImplements(selector, current) {
            owner = class_getSuperclass(current)
        }
        guard let owner, patchedOwners.insert(ObjectIdentifier(owner)).inserted else { return }
        guard let method = class_getInstanceMethod(owner, selector) else { return }
        let original = method_getImplementation(method)
        let block: @convention(block) (AnyObject) -> Int = { object in
            if let number = objc_getAssociatedObject(object, &styleKey) as? NSNumber {
                return number.intValue
            }
            let function = unsafeBitCast(original, to: (@convention(c) (AnyObject, Selector) -> Int).self)
            return function(object, selector)
        }
        method_setImplementation(method, imp_implementationWithBlock(block))
    }

    private static func classImplements(_ selector: Selector, _ cls: AnyClass) -> Bool {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else { return false }
        defer { free(methods) }
        for index in 0..<Int(count) where method_getName(methods[index]) == selector {
            return true
        }
        return false
    }
}
