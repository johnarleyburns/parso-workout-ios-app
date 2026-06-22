import SwiftUI

struct SplashView: View {
    @Binding var isPresented: Bool
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.85

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

            Color.black.opacity(0.35)

            VStack(spacing: 10) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)

                Text("Cladiron")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)

                Text("Your strength coach")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
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
                withAnimation(.easeOut(duration: 0.4)) {
                    opacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    isPresented = false
                }
            }
        }
    }
}
