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

    /// Validity of e1RM prediction equations — anchors the strength-assessment
    /// (estimated-1RM / rep-max) insights added in P4.
    public static let oneRMEstimation = Citation(
        id: "oneRMEstimation",
        authors: "LeSuer, McCormick, Mayhew, Wasserman & Arnold",
        year: 1997,
        title: "The Accuracy of Prediction Equations for Estimating 1-RM Performance in the Bench Press, Squat, and Deadlift",
        source: "Journal of Strength and Conditioning Research 11(4)",
        url: "https://journals.lww.com/nsca-jscr/abstract/1997/11000/the_accuracy_of_prediction_equations_for.1.aspx"
    )

    /// RIR-based RPE autoregulation — anchors the prescriptive phase's
    /// progression (double progression toward a target RIR) and deload rules (P5).
    public static let rpeAutoregulation = Citation(
        id: "rpeAutoregulation",
        authors: "Helms, Cronin, Storey & Zourdos",
        year: 2016,
        title: "Application of the Repetitions in Reserve-Based Rating of Perceived Exertion Scale for Resistance Training",
        source: "Strength and Conditioning Journal 38(4)",
        url: "https://journals.lww.com/nsca-scj/fulltext/2016/08000/application_of_the_repetitions_in_reserve_based.10.aspx"
    )

    /// Cooper 12-minute run test validity — anchors the VO₂max assessment insight (P6).
    public static let cooperVo2max = Citation(
        id: "cooperVo2max",
        authors: "Cooper",
        year: 1968,
        title: "A means of assessing maximal oxygen intake: Correlation between field and treadmill testing",
        source: "JAMA 203(3)",
        url: "https://doi.org/10.1001/jama.1968.03140030033008"
    )

    /// Wingate anaerobic test reliability — anchors the Wingate assessment insight (P6).
    public static let wingateTest = Citation(
        id: "wingateTest",
        authors: "Bar-Or",
        year: 1987,
        title: "The Wingate anaerobic test: An update on methodology, reliability and validity",
        source: "Sports Medicine 4(6)",
        url: "https://doi.org/10.2165/00007256-198704060-00005"
    )

    /// HIIT improves VO₂max — anchors the cardioHIIT prescription rule (P6).
    public static let hiitVo2max = Citation(
        id: "hiitVo2max",
        authors: "Helgerud, Hoydal, Wang, Karlsen, Berg, Bjerkaas, Simonsen, Helgesen, Hjorth, Bach & Hoff",
        year: 2007,
        title: "Aerobic high-intensity intervals improve VO\u{2082}max more than moderate training",
        source: "Medicine & Science in Sports & Exercise 39(4)",
        url: "https://doi.org/10.1249/mss.0b013e3180304570"
    )

    public static let run1_5mile = Citation(
        id: "run1_5mile",
        authors: "American College of Sports Medicine",
        year: 2021,
        title: "ACSM\u{2019}s Guidelines for Exercise Testing and Prescription (11th ed.)",
        source: "Wolters Kluwer",
        url: "https://www.acsm.org/education-resources/books/guidelines-exercise-testing-prescription"
    )

    public static let rockportWalk = Citation(
        id: "rockportWalk",
        authors: "Kline, Porcari, Hintermeister, Freedson, Ward, McCarron, Ross & Rippe",
        year: 1987,
        title: "Estimation of VO\u{2082}max from a one-mile track walk, gender, age, and body weight",
        source: "Medicine & Science in Sports & Exercise 19(3)",
        url: "https://doi.org/10.1249/00005768-198706000-00013"
    )

    public static let queensCollegeStep = Citation(
        id: "queensCollegeStep",
        authors: "McArdle, Katch, Pechar, Jacobson & Ruck",
        year: 1972,
        title: "Reliability and interrelationships between maximal oxygen intake, physical work capacity and step-test scores in college women",
        source: "Medicine and Science in Sports 4(4)",
        url: "https://doi.org/10.1249/00005768-197200440-00019"
    )

    public static let all: [Citation] = [schoenfeld2021, volumeDoseResponse, frequencyMeta, oneRMEstimation, rpeAutoregulation, cooperVo2max, wingateTest, hiitVo2max, run1_5mile, rockportWalk, queensCollegeStep]

    public static func citation(forId id: String) -> Citation? {
        all.first { $0.id == id }
    }
}
