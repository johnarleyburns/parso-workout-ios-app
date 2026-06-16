import SwiftUI

/// Placeholder for the **Library** tab (strength-pivot P3 ships the tab; content
/// lands in a later phase). Future home for the full exercise library (images,
/// muscles, instructions), prebuilt routines (5×5 etc.), and the published studies
/// behind the coaching.
struct LibraryView: View {
    var body: some View {
        NavigationStack {
            ComingSoonPlaceholder(
                systemImage: "books.vertical",
                title: "Library",
                message: "Browse every exercise, prebuilt routines, and the studies behind your coaching here.",
                identifier: "library.placeholder")
            .navigationTitle("Library")
        }
    }
}
