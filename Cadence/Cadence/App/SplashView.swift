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

            feTile
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

    private var feTile: some View {
        VStack(spacing: 3) {
            HStack {
                Text("26")
                    .font(.caption2.weight(.semibold))
                Spacer()
            }
            Text("Fe")
                .font(.system(size: 42, weight: .bold, design: .serif))
                .minimumScaleFactor(0.8)
            Text("Iron")
                .font(.caption.weight(.semibold))
            Text("55.845")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.82))
        }
        .foregroundStyle(.white)
        .frame(width: 92, height: 108)
        .padding(10)
        .background(.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(.white.opacity(0.82), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Iron, Fe, atomic number 26, atomic weight 55.845")
    }
}
