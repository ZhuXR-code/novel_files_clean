import SwiftUI

extension Color {
    static let fsPrimary = Color("AccentColor")
    static let fsBg = Color(.systemBackground)
    static let fsSecondaryBg = Color(.secondarySystemBackground)
    static let fsTertiaryBg = Color(.tertiarySystemBackground)
    static let fsLabel = Color(.label)
    static let fsSecondaryLabel = Color(.secondaryLabel)
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
            Text(title).font(.headline).foregroundColor(.fsSecondaryLabel)
            content
                .padding(12)
                .background(Color.fsSecondaryBg)
                .cornerRadius(12)
        }
    }
}
