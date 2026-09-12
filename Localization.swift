import Foundation

enum AppLanguage: String, CaseIterable {
    case english
    case simplifiedChinese

    static var systemDefault: AppLanguage {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        return preferred.hasPrefix("zh") ? .simplifiedChinese : .english
    }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }
}

enum L10n {
    enum Key: CaseIterable {
        case tapEnabled
        case tapDisabled
        case mouseConnected
        case mouseDisconnected
        case rightClickZone
        case language
        case accessibilityInstructions
        case about
        case quit
        case accessibilityRequired
        case openSystemSettings
        case close
        case tapToClickSubtitle
        case leftTapHelp
        case rightTapHelp
        case maintainer
        case projectURL
        case version
        case privateFrameworkNotice
        case ok
    }

    static func string(_ key: Key, language: AppLanguage = Preferences.appLanguage) -> String {
        switch (language, key) {
        case (.english, .tapEnabled): return "Tap to Click: Enabled"
        case (.english, .tapDisabled): return "Tap to Click: Disabled"
        case (.english, .mouseConnected): return "Magic Mouse: Connected"
        case (.english, .mouseDisconnected): return "Magic Mouse: Disconnected"
        case (.english, .rightClickZone): return "Right Click Zone"
        case (.english, .language): return "Language"
        case (.english, .accessibilityInstructions): return "Accessibility Instructions…"
        case (.english, .about): return "About"
        case (.english, .quit): return "Quit"
        case (.english, .accessibilityRequired): return "Accessibility Permission Required"
        case (.english, .openSystemSettings): return "Open System Settings"
        case (.english, .close): return "Close"
        case (.english, .tapToClickSubtitle): return "Tap-to-click for Magic Mouse"
        case (.english, .leftTapHelp): return "Tap left side for left click"
        case (.english, .rightTapHelp): return "Tap right side for right click"
        case (.english, .maintainer): return "Maintained by woodonchan"
        case (.english, .projectURL): return "GitHub: https://github.com/wudongchen/MouseToucher"
        case (.english, .version): return "Version"
        case (.english, .privateFrameworkNotice): return "Uses private MultitouchSupport framework"
        case (.english, .ok): return "OK"

        case (.simplifiedChinese, .tapEnabled): return "轻触点击：已启用"
        case (.simplifiedChinese, .tapDisabled): return "轻触点击：已停用"
        case (.simplifiedChinese, .mouseConnected): return "妙控鼠标：已连接"
        case (.simplifiedChinese, .mouseDisconnected): return "妙控鼠标：未连接"
        case (.simplifiedChinese, .rightClickZone): return "右键区域"
        case (.simplifiedChinese, .language): return "语言"
        case (.simplifiedChinese, .accessibilityInstructions): return "辅助功能授权说明…"
        case (.simplifiedChinese, .about): return "关于"
        case (.simplifiedChinese, .quit): return "退出"
        case (.simplifiedChinese, .accessibilityRequired): return "需要辅助功能权限"
        case (.simplifiedChinese, .openSystemSettings): return "打开系统设置"
        case (.simplifiedChinese, .close): return "关闭"
        case (.simplifiedChinese, .tapToClickSubtitle): return "为妙控鼠提供轻触点击"
        case (.simplifiedChinese, .leftTapHelp): return "轻触左侧执行左键点击"
        case (.simplifiedChinese, .rightTapHelp): return "轻触右侧执行右键点击"
        case (.simplifiedChinese, .maintainer): return "维护者：woodonchan"
        case (.simplifiedChinese, .projectURL): return "GitHub 项目：https://github.com/wudongchen/MouseToucher"
        case (.simplifiedChinese, .version): return "版本"
        case (.simplifiedChinese, .privateFrameworkNotice): return "使用系统私有 MultitouchSupport 框架"
        case (.simplifiedChinese, .ok): return "好"
        }
    }

    static func rightSideStarts(at percent: Int, language: AppLanguage = Preferences.appLanguage) -> String {
        switch language {
        case .english: return "Right side starts at \(percent)%"
        case .simplifiedChinese: return "右侧从 \(percent)% 开始"
        }
    }

    static func accessibilityDetail(language: AppLanguage = Preferences.appLanguage) -> String {
        switch language {
        case .english:
            return """
            Mouse Toucher needs accessibility permission to simulate clicks.

            Grant permission in:
            System Settings > Privacy & Security > Accessibility

            After enabling it, return to Mouse Toucher. The app will begin working automatically.
            """
        case .simplifiedChinese:
            return """
            Mouse Toucher 需要辅助功能权限来模拟鼠标点击。

            请前往：
            系统设置 > 隐私与安全性 > 辅助功能

            打开权限后返回 Mouse Toucher，程序会自动开始工作。
            """
        }
    }
}
