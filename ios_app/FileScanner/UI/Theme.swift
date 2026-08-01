import SwiftUI

extension Color {
    static let fsPrimary = Color("AccentColor")
    static let fsBg = Color(.systemBackground)
    static let fsSecondaryBg = Color(.secondarySystemBackground)
    static let fsTertiaryBg = Color(.tertiarySystemBackground)
    static let fsLabel = Color(.label)
    static let fsSecondaryLabel = Color(.secondaryLabel)
    static let fsSeparator = Color(.separator)
}

// MARK: - 字号缩放（跟随设置中的 小/标准/大）
extension View {
    /// 按当前字号偏好缩放系统文本样式。
    func fsFont(_ style: Font.TextStyle, design: Font.Design = .default) -> some View {
        let scale = Preferences.shared.fontScaleFactor
        return self.font(.system(size: Font_TextStyleSize(style) * scale, design: design))
    }

    /// 按当前字号偏好缩放固定 pt 字号（用于图标、数字等）。
    func fsFontSize(_ size: CGFloat) -> some View {
        let scale = Preferences.shared.fontScaleFactor
        return self.font(.system(size: size * scale))
    }
}

/// 各文本样式的基准 pt（对齐 iOS 默认 Dynamic Type 基准，用于按比例缩放）。
private func Font_TextStyleSize(_ style: Font.TextStyle) -> CGFloat {
    switch style {
    case .largeTitle: return 34
    case .title:      return 28
    case .title2:     return 22
    case .title3:     return 20
    case .headline:   return 17
    case .body:       return 17
    case .callout:    return 16
    case .subheadline:return 15
    case .footnote:   return 13
    case .caption:    return 12
    case .caption2:   return 11
    default:          return 17
    }
}

struct FSSection<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).fsFont(.headline).foregroundColor(.fsSecondaryLabel)
            content
                .padding(12)
                .background(Color.fsSecondaryBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.fsSeparator, lineWidth: 0.5)
                )
                .cornerRadius(10)
        }
    }
}
