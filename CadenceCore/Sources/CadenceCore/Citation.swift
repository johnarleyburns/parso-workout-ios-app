import Foundation

/// A published reference an engine `Insight`/recommendation is grounded in
/// (strength-pivot decision D3: every coaching output shows its "why + the
/// science"). The set is intentionally small and conservatively worded for P3;
/// a full curated `CITATIONS.md` pass precedes the prescriptive phase (D9).
public struct Citation: Equatable, Hashable, Sendable, Identifiable {
    public let id: String          // stable key, e.g. "schoenfeld2021"
    public let authors: String     // "Schoenfeld, Grgic, Van Every & Plotkin"
    public let year: Int
    public let title: String
    public let source: String      // journal / publication
    public let url: String         // canonical link (open-access where possible)

    public init(id: String, authors: String, year: Int, title: String, source: String, url: String) {
        self.id = id
        self.authors = authors
        self.year = year
        self.title = title
        self.source = source
        self.url = url
    }

    /// A compact one-line attribution, e.g. "Schoenfeld et al. (2021), Sports".
    public var shortText: String {
        let lead = authors.contains("&") || authors.contains(",")
            ? "\(authors.split(separator: " ").first.map(String.init) ?? authors) et al."
            : authors
        return "\(lead) (\(year)), \(source)"
    }
}

/// The bundled reference list the P3 rules point at. Open-source + visible in-app.
public enum CitationRegistry {

    /// Anchor paper for the intensity×goal rule (user-supplied).
    public static let schoenfeld2021 = Citation(
        id: "schoenfeld2021",
        authors: "Schoenfeld, Grgic, Van Every & Plotkin",
        year: 2021,
        title: "Loading Recommendations for Muscle Strength, Hypertrophy, and Local Endurance: A Re-Examination of the Repetition Continuum",
        source: "Sports 9(2):32",
        url: "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7927075/"
    )

    /// Weekly-volume dose-response — anchors the MEV/MAV/MRV volume landmarks.
    public static let volumeDoseResponse = Citation(
        id: "volumeDoseResponse",
        authors: "Schoenfeld, Ogborn & Krieger",
        year: 2017,
        title: "Dose-response relationship between weekly resistance training volume and increases in muscle mass: A systematic review and meta-analysis",
        source: "Journal of Sports Sciences 35(11)",
        url: "https://doi.org/10.1080/02640414.2016.1210197"
    )

    /// Training-frequency meta-analysis — anchors the ≥2 sessions/muscle/week rule.
    public static let frequencyMeta = Citation(
        id: "frequencyMeta",
        authors: "Schoenfeld, Grgic & Krieger",
        year: 2019,
        title: "How many times per week should a muscle be trained to maximize muscle hypertrophy? A systematic review and meta-analysis",
        source: "Journal of Sports Sciences 37(11)",
        url: "https://doi.org/10.1080/02640414.2018.1555906"
    )

    /// All citations, for the in-app references list and tests.
    public static let all: [Citation] = [schoenfeld2021, volumeDoseResponse, frequencyMeta]
}
