import SwiftUI

struct SplashView: View {
    @Binding var isPresented: Bool
    @State private var opacity: Double = 0
    @State private var scale: Double = 0.85

    var body: some View {
        ZStack {
            Color(.systemGray6)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text("Cladiron")
                    .font(.largeTitle.weight(.bold))

                Text("Your strength coach")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
