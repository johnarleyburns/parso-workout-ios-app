import SwiftUI

struct SplashView: View {
    @Binding var isPresented: Bool
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.85

    private var appIcon: UIImage? {
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
           let lastIcon = iconFiles.last {
            return UIImage(named: lastIcon)
        }
        return nil
    }

    var body: some View {
        ZStack {
            if let img = UIImage(named: "splash") {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipped()
            } else {
                Color(.systemBackground)
            }

            Color.black.opacity(0.55)

            VStack(spacing: 14) {
                if let icon = appIcon {
                    Image(uiImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(.white.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 8)
                } else {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white)
                }

                Text("Cladiron")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)

                Text("Your strength coach")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .scaleEffect(scale)
            .opacity(opacity)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7)) {
                opacity = 1
                scale = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.4)) { opacity = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    isPresented = false
                }
            }
        }
    }
}
