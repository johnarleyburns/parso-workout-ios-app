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

    // MARK: - Routine program citations (2026-06-19 science audit)

    public static let krieger2010 = Citation(
        id: "krieger2010",
        authors: "Krieger",
        year: 2010,
        title: "Single vs. Multiple Sets of Resistance Exercise for Muscle Hypertrophy: A Meta-Analysis",
        source: "Journal of Strength and Conditioning Research 24(4)",
        url: "https://doi.org/10.1519/JSC.0b013e3181d4d436"
    )

    public static let rheaPeriodization = Citation(
        id: "rheaPeriodization",
        authors: "Rhea & Alderman",
        year: 2004,
        title: "A Meta-Analysis of Periodized Versus Nonperiodized Strength and Power Training Programs",
        source: "Research Quarterly for Exercise and Sport 75(4)",
        url: "https://doi.org/10.1080/02701367.2004.10609174"
    )

    public static let calatayudBodyweight = Citation(
        id: "calatayudBodyweight",
        authors: "Calatayud, Borreani, Colado, Martin, Tella & Andersen",
        year: 2015,
        title: "Bench Press and Push-Up at Comparable Levels of Muscle Activity Results in Similar Strength Gains",
        source: "Journal of Strength and Conditioning Research 29(1)",
        url: "https://doi.org/10.1519/JSC.0000000000000589"
    )

    public static let channellOlympic = Citation(
        id: "channellOlympic",
        authors: "Channell & Barfield",
        year: 2008,
        title: "Effect of Olympic and Traditional Resistance Training on Vertical Jump Improvement in High School Boys",
        source: "Journal of Strength and Conditioning Research 22(5)",
        url: "https://doi.org/10.1519/JSC.0b013e318181a3d0"
    )

    public static let zourdosDUP = Citation(
        id: "zourdosDUP",
        authors: "Zourdos, Jo, Khamoui, Lee, Park, Henning, Weiss & Kim",
        year: 2016,
        title: "Modified Daily Undulating Periodization Model Produces Greater Performance Than a Traditional Configuration in Powerlifters",
        source: "Journal of Strength and Conditioning Research 30(3)",
        url: "https://doi.org/10.1519/JSC.0000000000001165"
    )

    public static let amirthalingamGVT = Citation(
        id: "amirthalingamGVT",
        authors: "Amirthalingam, Mavros, Wilson, Clarke, Mitchell & Hackett",
        year: 2017,
        title: "Effects of a Modified German Volume Training Program on Muscular Hypertrophy and Strength",
        source: "Journal of Strength and Conditioning Research 31(11)",
        url: "https://doi.org/10.1519/JSC.0000000000001747"
    )

    public static let williamsLinearPeriodization = Citation(
        id: "williamsLinearPeriodization",
        authors: "Williams, Tolusso, Fedewa & Esco",
        year: 2017,
        title: "Comparison of Periodized and Non-Periodized Resistance Training on Maximal Strength: A Meta-Analysis",
        source: "Sports Medicine 47(10)",
        url: "https://doi.org/10.1007/s40279-017-0734-y"
    )

    public static let tufanoCluster = Citation(
        id: "tufanoCluster",
        authors: "Tufano, Brown & Haff",
        year: 2017,
        title: "Theoretical and Practical Aspects of Different Cluster Set Structures: A Systematic Review",
        source: "Journal of Strength and Conditioning Research 31(3)",
        url: "https://doi.org/10.1519/JSC.0000000000001581"
    )

    // MARK: - New citations for recovery-aware redesign (2026-06-22)

    public static let ekelundActivityMortality2016 = Citation(
        id: "ekelundActivityMortality2016",
        authors: "Ekelund, Steene-Johannessen, Brown, Fagerland, Owen, Powell, Bauman & Lee",
        year: 2016,
        title: "Does physical activity attenuate, or even eliminate, the detrimental association of sitting time with mortality?",
        source: "The Lancet 388(10051)",
        url: "https://doi.org/10.1016/S0140-6736(16)30370-1"
    )

    public static let pellandDoseResponse2026 = Citation(
        id: "pellandDoseResponse2026",
        authors: "Pelland, Schoenfeld, Grgic, O'Connor, Campbell & Haun",
        year: 2026,
        title: "Dose-response relationship between weekly resistance training volume and muscular adaptations",
        source: "Sports Medicine",
        url: "https://pubmed.ncbi.nlm.nih.gov/41343037/"
    )

    public static let ramosCampoSplit2024 = Citation(
        id: "ramosCampoSplit2024",
        authors: "Ramos-Campo, Andreu, Guerrero, Vera-Ibanez, Avila-Gandia & Rubio-Arias",
        year: 2024,
        title: "Effects of full-body and split routines on strength and hypertrophy",
        source: "Sports Medicine",
        url: "https://pubmed.ncbi.nlm.nih.gov/38595233/"
    )

    public static let parejaBlancoRecovery2020 = Citation(
        id: "parejaBlancoRecovery2020",
        authors: "Pareja-Blanco, Rodriguez-Rosell, Aagaard & Gonzalez-Badillo",
        year: 2020,
        title: "Recovery of neuromuscular performance after resistance training to failure",
        source: "European Journal of Applied Physiology",
        url: "https://pubmed.ncbi.nlm.nih.gov/30036284/"
    )

    public static let sawMonitoring2016 = Citation(
        id: "sawMonitoring2016",
        authors: "Saw, Main & Gastin",
        year: 2016,
        title: "Monitoring athletes through self-report: Factors influencing implementation",
        source: "Journal of Sports Science and Medicine",
        url: "https://pubmed.ncbi.nlm.nih.gov/26423706/"
    )

    public static let meeusenOvertraining2013 = Citation(
        id: "meeusenOvertraining2013",
        authors: "Meeusen, Duclos, Foster, Fry, Gleeson, Nieman, Raglin, Rietjens, Steinacker & Urhausen",
        year: 2013,
        title: "Prevention, diagnosis and treatment of the overtraining syndrome: ECSS/ACSM consensus",
        source: "Medicine & Science in Sports & Exercise",
        url: "https://pubmed.ncbi.nlm.nih.gov/23247672/"
    )

    public static let schumannConcurrent2022 = Citation(
        id: "schumannConcurrent2022",
        authors: "Schumann, Feuerbacher, Sunkeler, Freitag, Ronnestad, Doma & Lundberg",
        year: 2022,
        title: "Compatibility of concurrent aerobic and strength training: A systematic review",
        source: "Sports Medicine",
        url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC8891239/"
    )

    public static let crowleyVO2Intensity2022 = Citation(
        id: "crowleyVO2Intensity2022",
        authors: "Crowley, Miller, O'Connor & Harrison",
        year: 2022,
        title: "Effects of high-intensity interval training and moderate-intensity continuous training on VO2max",
        source: "Sports Medicine",
        url: "https://pubmed.ncbi.nlm.nih.gov/38655159/"
    )

    public static let poonHIIT2024 = Citation(
        id: "poonHIIT2024",
        authors: "Poon, Li, Wong, Chung & Wong",
        year: 2024,
        title: "HIIT versus MICT for cardiorespiratory fitness: An umbrella review",
        source: "Sports Medicine",
        url: "https://pubmed.ncbi.nlm.nih.gov/38760916/"
    )

    // MARK: - Aerobic/activity research citations (no public-health guidelines)

    public static let mooreLeisureActivity2012 = Citation(
        id: "mooreLeisureActivity2012",
        authors: "Moore, Patel, Matthews, Berrington de Gonzalez, Park, Katki, Linet, Weiderpass, Visvanathan, Helzlsouer, Thun, Gapstur, Hartge & Lee",
        year: 2012,
        title: "Leisure time physical activity of moderate to vigorous intensity and mortality: a large pooled cohort analysis",
        source: "PLOS Medicine 9(11)",
        url: "https://journals.plos.org/plosmedicine/article?id=10.1371/journal.pmed.1001335"
    )

    public static let aremDoseResponse2015 = Citation(
        id: "aremDoseResponse2015",
        authors: "Arem, Moore, Patel, Hartge, Berrington de Gonzalez, Visvanathan, Campbell, Freedman, Weiderpass, Adami, Linet, Lee & Matthews",
        year: 2015,
        title: "Leisure time physical activity and mortality: a detailed pooled analysis of the dose-response relationship",
        source: "JAMA Internal Medicine 175(6)",
        url: "https://jamanetwork.com/journals/jamainternalmedicine/fullarticle/2212267"
    )

    public static let saintMauriceSteps2020 = Citation(
        id: "saintMauriceSteps2020",
        authors: "Saint-Maurice, Troiano, Bassett, Graubard, Carlson, Shiroma, Fulton & Matthews",
        year: 2020,
        title: "Association of daily step count and step intensity with mortality among US adults",
        source: "JAMA 323(12)",
        url: "https://doi.org/10.1001/jama.2020.1382"
    )

    public static let leeAccelerometer2019 = Citation(
        id: "leeAccelerometer2019",
        authors: "Lee, Shiroma, Kamada, Bassett, Matthews & Buring",
        year: 2019,
        title: "Association of step volume and intensity with all-cause mortality in older women",
        source: "JAMA Internal Medicine 179(8)",
        url: "https://doi.org/10.1001/jamainternmed.2019.0899"
    )

    // MARK: - Recovery/load research citations

    public static let halsonRecovery2014 = Citation(
        id: "halsonRecovery2014",
        authors: "Halson",
        year: 2014,
        title: "Monitoring training load to understand fatigue in athletes",
        source: "Sports Medicine 44(Suppl 2)",
        url: "https://doi.org/10.1007/s40279-014-0253-z"
    )

    public static let drewFinchInjury2016 = Citation(
        id: "drewFinchInjury2016",
        authors: "Drew & Finch",
        year: 2016,
        title: "The relationship between training load and injury, illness and soreness: a systematic and literature review",
        source: "Sports Medicine 46(6)",
        url: "https://link.springer.com/article/10.1007/s40279-015-0459-8"
    )

    public static let dupuyFatigue2018 = Citation(
        id: "dupuyFatigue2018",
        authors: "Dupuy, Douzi, Theurot, Bosquet & Dugue",
        year: 2018,
        title: "An evidence-based approach for choosing post-exercise recovery techniques to reduce markers of muscle damage, soreness, fatigue, and inflammation: a systematic review with meta-analysis",
        source: "Frontiers in Physiology 9",
        url: "https://doi.org/10.3389/fphys.2018.00403"
    )

    // MARK: - All citations registry

    public static let all: [Citation] = [
        schoenfeld2021, volumeDoseResponse, frequencyMeta, oneRMEstimation,
        rpeAutoregulation, cooperVo2max, wingateTest, hiitVo2max,
        rockportWalk, queensCollegeStep,
        krieger2010, rheaPeriodization, calatayudBodyweight, channellOlympic,
        zourdosDUP, amirthalingamGVT, williamsLinearPeriodization, tufanoCluster,
        ekelundActivityMortality2016,
        pellandDoseResponse2026, ramosCampoSplit2024, parejaBlancoRecovery2020,
        sawMonitoring2016, meeusenOvertraining2013, schumannConcurrent2022,
        crowleyVO2Intensity2022, poonHIIT2024,
        mooreLeisureActivity2012, aremDoseResponse2015, saintMauriceSteps2020,
        leeAccelerometer2019,
        halsonRecovery2014, drewFinchInjury2016, dupuyFatigue2018,
    ]

    public static func citation(forId id: String) -> Citation? {
        all.first { $0.id == id }
    }

    // MARK: - Citation pools for deterministic rotation

    public static let aerobicPool = CitationPool(id: "aerobic", citationIds: [
        "mooreLeisureActivity2012",
        "aremDoseResponse2015",
        "saintMauriceSteps2020",
        "leeAccelerometer2019",
        "ekelundActivityMortality2016",
    ])

    public static let recoveryLoadPool = CitationPool(id: "recoveryLoad", citationIds: [
        "halsonRecovery2014",
        "drewFinchInjury2016",
        "sawMonitoring2016",
        "parejaBlancoRecovery2020",
        "schumannConcurrent2022",
        "dupuyFatigue2018",
    ])
}
