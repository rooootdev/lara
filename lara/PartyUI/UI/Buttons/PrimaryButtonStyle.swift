import SwiftUI

public struct PrimaryButtonStyle: PrimitiveButtonStyle {

    private var color: Color
    private var useFullWidth: Bool
    private var isLoading: Bool

    @Environment(\.isEnabled) private var isEnabled

    public init(
        color: Color = .accentColor,
        useFullWidth: Bool = true,
        isLoading: Bool = false
    ) {
        self.color = color
        self.useFullWidth = useFullWidth
        self.isLoading = isLoading
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(isEnabled ? .white : .white.opacity(0.6))
            .frame(maxWidth: useFullWidth ? .infinity : nil)
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(
                Capsule(style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
            .onTapGesture {
                guard isEnabled, !isLoading else { return }
                configuration.trigger()

                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
            }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if !isEnabled { return .gray.opacity(0.3) }
        return isPressed ? color.opacity(0.85) : color
    }
}
