import SwiftUI

struct SplashView: View {
    @Binding var isPresented: Bool
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.85

    var body: some View {
        ZStack {
            if let image = UIImage(named: "splash") {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                    .clipped()
            } else {
                Color(.systemGray6)
                    .ignoresSafeArea()
            }

            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 14) {
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
