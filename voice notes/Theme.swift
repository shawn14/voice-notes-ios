import SwiftUI

// Convenience alias — Xcode auto-generates Color.eeonAccent, .eeonBackground, etc.
// from the asset catalog. We only need to add aliases for names that differ.
extension Color {
    /// Alias for EEONCardBackground (shorter name for convenience)
    static let eeonCard = Color("EEONCardBackground")
}

// Card style modifier for consistent card appearance
struct EEONCardStyle: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        content
            .background(Color.eeonCard)
            .cornerRadius(16)
            .shadow(color: colorScheme == .dark ? .clear : Color.black.opacity(0.06), radius: 8, y: 2)
    }
}

extension View {
    func eeonCard() -> some View {
        modifier(EEONCardStyle())
    }
}
