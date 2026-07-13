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

/// The class of claim a coaching output makes. Every claim that surfaces a
/// citation carries one of these so a citation pool curated for one claim class can
/// never be reused for an unrelated one (the 2026-06-25 evidence upgrade). Resolve a
/// category to its pool with `CitationRegistry.citationPool(for:)`.
public enum EvidenceClaimCategory: String, Sendable, Codable, CaseIterable {
    case activityMinutesHealth
    case stepsHealth
    case strengthFrequency
    case strengthVolume
    case strengthIntensity
    case periodization
    case aerobicBase
    case vo2Training
    case thresholdTraining
    case anaerobicTraining
    case flexibilityROM
    case recoveryMonitoring
    case concurrentTraining
    case fieldTestValidity
    case schedulePreference
    case publicHealthGuideline
    case sessionStructure
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
        url: "https://doi.org/10.2165/00007256-198704060-00001"
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
        authors: "Pelland, Remmert, Robinson, Hinson & Zourdos",
        year: 2026,
        title: "The Resistance Training Dose Response: Meta-Regressions Exploring the Effects of Weekly Volume and Frequency on Muscle Hypertrophy and Strength Gains",
        source: "Sports Medicine",
        url: "https://doi.org/10.1007/s40279-025-02344-w"
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
        title: "Monitoring the athlete training response: subjective self-reported measures trump commonly used objective measures: a systematic review",
        source: "British Journal of Sports Medicine 50(5)",
        url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC4789708/"
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
        authors: "Crowley, Powell, Bottoms & Sykes",
        year: 2022,
        title: "The Effect of Exercise Training Intensity on VO\u{2082}max in Healthy Adults: An Overview of Systematic Reviews and Meta-Analyses",
        source: "Translational Sports Medicine",
        url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC11022784/"
    )

    public static let poonHIIT2024 = Citation(
        id: "poonHIIT2024",
        authors: "Poon, Sheridan, Chung, Wong & Sun",
        year: 2024,
        title: "High-intensity interval training and cardiorespiratory fitness in adults: An umbrella review of systematic reviews and meta-analyses",
        source: "Scandinavian Journal of Medicine & Science in Sports 34(5)",
        url: "https://doi.org/10.1111/sms.14652"
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

    // MARK: - Coach evidence-upgrade citations (2026-06-25)

    /// RIR-anchored RPE scale validation — distinct from the application paper
    /// (`rpeAutoregulation`); used for strength-intensity / autoregulation claims.
    public static let zourdosRIR2016 = Citation(
        id: "zourdosRIR2016",
        authors: "Zourdos, Klemp, Dolan, Quiles, Schau, Jo, Helms, Esgro, Duncan, Garcia Merino & Blanco",
        year: 2016,
        title: "Novel Resistance Training-Specific Rating of Perceived Exertion Scale Measuring Repetitions in Reserve",
        source: "Journal of Strength and Conditioning Research 30(1)",
        url: "https://doi.org/10.1519/JSC.0000000000001049"
    )

    /// Age-predicted HRmax equation — used to label HR-zone uncertainty when max HR
    /// is estimated rather than tested.
    public static let tanakaMaxHR2001 = Citation(
        id: "tanakaMaxHR2001",
        authors: "Tanaka, Monahan & Seals",
        year: 2001,
        title: "Age-predicted maximal heart rate revisited",
        source: "Journal of the American College of Cardiology 37(1)",
        url: "https://doi.org/10.1016/s0735-1097(00)01054-8"
    )

    /// Intensity-distribution / polarized training — backs how weekly cardio time
    /// is spread across HR zones (mostly easy, some hard) for endurance adaptation.
    public static let seilerPolarized2010 = Citation(
        id: "seilerPolarized2010",
        authors: "Seiler",
        year: 2010,
        title: "What is best practice for training intensity and duration distribution in endurance athletes?",
        source: "International Journal of Sports Physiology and Performance 5(3)",
        url: "https://doi.org/10.1123/ijspp.5.3.276"
    )

    /// Threshold-method agreement / uncertainty — used for threshold/lactate claims.
    public static let kaufmannThreshold2023 = Citation(
        id: "kaufmannThreshold2023",
        authors: "Kaufmann, Gronwald, Herold & Hoos",
        year: 2023,
        title: "Heart Rate Variability-Derived Thresholds for Exercise Intensity Prescription in Endurance Sports: A Systematic Review of Interrelations and Agreement with Different Ventilatory and Blood Lactate Thresholds",
        source: "Sports Medicine - Open 9(1)",
        url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC10354346/"
    )

    /// HIIT vs continuous training for VO₂max — VO2-training claims.
    public static let milanovicHIIT2015 = Citation(
        id: "milanovicHIIT2015",
        authors: "Milanovic, Sporis & Weston",
        year: 2015,
        title: "Effectiveness of High-Intensity Interval Training (HIT) and Continuous Endurance Training for VO\u{2082}max Improvements: A Systematic Review and Meta-Analysis of Controlled Trials",
        source: "Sports Medicine 45(10)",
        url: "https://doi.org/10.1007/s40279-015-0365-0"
    )

    /// Sprint interval training effects — short, hard anaerobic interval claims.
    public static let slothSIT2013 = Citation(
        id: "slothSIT2013",
        authors: "Sloth, Sloth, Overgaard & Dalgas",
        year: 2013,
        title: "Effects of sprint interval training on VO\u{2082}max and aerobic exercise performance: A systematic review and meta-analysis",
        source: "Scandinavian Journal of Medicine & Science in Sports 23(6)",
        url: "https://doi.org/10.1111/sms.12092"
    )

    /// HIIT programming, anaerobic energy + neuromuscular load (Part II) — anaerobic claims.
    public static let buchheitLaursenHIIT2013 = Citation(
        id: "buchheitLaursenHIIT2013",
        authors: "Buchheit & Laursen",
        year: 2013,
        title: "High-Intensity Interval Training, Solutions to the Programming Puzzle: Part II: Anaerobic Energy, Neuromuscular Load and Practical Applications",
        source: "Sports Medicine 43(10)",
        url: "https://doi.org/10.1007/s40279-013-0066-5"
    )

    /// Chronic stretching and ROM gains — flexibility/ROM claims.
    public static let konradStretchROM2024 = Citation(
        id: "konradStretchROM2024",
        authors: "Konrad, Alizadeh, Daneshjoo, Anvar, Graham, Zahiri, Goudini, Edwards, Scharf & Behm",
        year: 2024,
        title: "Chronic effects of stretching on range of motion with consideration of potential moderating variables: A systematic review with meta-analysis",
        source: "Journal of Sport and Health Science 13(2)",
        url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC10980866/"
    )

    /// Acute stretching, ROM, performance and injury — flexibility/ROM claims; not a
    /// blanket injury-prevention claim.
    public static let behmStretching2016 = Citation(
        id: "behmStretching2016",
        authors: "Behm, Blazevich, Kay & McHugh",
        year: 2016,
        title: "Acute effects of muscle stretching on physical performance, range of motion, and injury incidence in healthy active individuals: a systematic review",
        source: "Applied Physiology, Nutrition, and Metabolism 41(1)",
        url: "https://doi.org/10.1139/apnm-2015-0235"
    )

    /// Exercise interventions and sports-injury prevention — strength/proprioceptive
    /// warm-up programs only, NOT static stretching alone.
    public static let lauersenInjuryPrevention2014 = Citation(
        id: "lauersenInjuryPrevention2014",
        authors: "Lauersen, Bertelsen & Andersen",
        year: 2014,
        title: "The effectiveness of exercise interventions to prevent sports injuries: a systematic review and meta-analysis of randomised controlled trials",
        source: "British Journal of Sports Medicine 48(11)",
        url: "https://doi.org/10.1136/bjsports-2013-092538"
    )

    /// General field-based adult fitness test reliability — fallback for bodyweight
    /// endurance benchmarks; not a population-validity claim for any single test.
    public static let fieldFitnessReliability2022 = Citation(
        id: "fieldFitnessReliability2022",
        authors: "Cuenca-Garcia, Marin-Jimenez, Perez-Bey, Sanchez-Oliva, Camiletti-Moiron, Alvarez-Gallardo, Ortega & Castro-Pinero",
        year: 2022,
        title: "Reliability of Field-Based Fitness Tests in Adults: A Systematic Review",
        source: "Sports Medicine 52(8)",
        url: "https://doi.org/10.1007/s40279-021-01635-2"
    )

    // MARK: - Schedule-preference / concurrent-training citations (2026-06-25)

    /// Concurrent-training sequence meta-analysis — anchors the "cardio after
    /// strength" default advice when strength is the priority.
    public static let murlasitsConcurrentSequence2018 = Citation(
        id: "murlasitsConcurrentSequence2018",
        authors: "Murlasits, Kneffel & Thalib",
        year: 2018,
        title: "The physiological effects of concurrent strength and endurance training sequence: A systematic review and meta-analysis",
        source: "Journal of Sports Sciences 36(11)",
        url: "https://doi.org/10.1080/02640414.2017.1364405"
    )

    public static let currierResistancePrescription2023 = Citation(
        id: "currierResistancePrescription2023",
        authors: "Currier, Mcleod, Banfield, Beyene, Welton, D'Souza, Keogh, Lin, Coletta, Yang, Colenso-Semple, Lau, Verboom & Phillips",
        year: 2023,
        title: "Resistance training prescription for muscle strength and hypertrophy in healthy adults: a systematic review and Bayesian network meta-analysis",
        source: "British Journal of Sports Medicine 57(18)",
        url: "https://doi.org/10.1136/bjsports-2023-106807"
    )

    /// Plank / global core-endurance test validity + reliability.
    public static let tongPlank2014 = Citation(
        id: "tongPlank2014",
        authors: "Tong, Wu & Nie",
        year: 2014,
        title: "Sport-specific endurance plank test for evaluation of global core muscle function",
        source: "Physical Therapy in Sport 15(1)",
        url: "https://doi.org/10.1016/j.ptsp.2013.03.003"
    )

    // MARK: - HIIT protocol citations (2026-07-08)

    /// Original Tabata protocol study — 20 s all-out bouts / 10 s rest, 7–8 sets.
    public static let tabata1996 = Citation(
        id: "tabata1996",
        authors: "Tabata, Nishimura, Kouzaki, Hirai, Ogita, Miyachi & Yamamoto",
        year: 1996,
        title: "Effects of moderate-intensity endurance and high-intensity intermittent training on anaerobic capacity and VO2max",
        source: "Medicine & Science in Sports & Exercise 28(10)",
        url: "https://doi.org/10.1097/00005768-199610000-00018"
    )

    /// Landmark short-term sprint interval training (SIT) study — 3 sessions/week of
    /// 4–6 × 30 s all-out Wingate sprints matched traditional endurance adaptations.
    public static let gibala2006 = Citation(
        id: "gibala2006",
        authors: "Gibala, Little, van Essen, Wilkin, Burgomaster, Safdar, Raha & Tarnopolsky",
        year: 2006,
        title: "Short-term sprint interval versus traditional endurance training: similar initial adaptations in human skeletal muscle and exercise performance",
        source: "Journal of Physiology 575(3)",
        url: "https://doi.org/10.1113/jphysiol.2006.112094"
    )

    /// Reduced-exertion high-intensity interval training (REHIT) — 2 × 20 s sprints
    /// within a 10-min session improved insulin sensitivity and VO₂max.
    public static let metcalfeREHIT2012 = Citation(
        id: "metcalfeREHIT2012",
        authors: "Metcalfe, Babraj, Fawkner & Vollaard",
        year: 2012,
        title: "Towards the minimal amount of exercise for improving metabolic health: beneficial effects of reduced-exertion high-intensity interval training",
        source: "European Journal of Applied Physiology 112(7)",
        url: "https://doi.org/10.1007/s00421-011-2254-z"
    )

    /// Original 10-20-30 training concept — 30 s low / 20 s moderate / 10 s sprint,
    /// 5 cycles per set, 2–4 sets — improved performance and health profile.
    public static let gunnarsson1020302012 = Citation(
        id: "gunnarsson1020302012",
        authors: "Gunnarsson & Bangsbo",
        year: 2012,
        title: "The 10-20-30 training concept improves performance and health profile in moderately trained runners",
        source: "Journal of Applied Physiology 113(1)",
        url: "https://doi.org/10.1152/japplphysiol.00334.2012"
    )

    public static let brennanExerciseClassification2025 = Citation(
        id: "brennanExerciseClassification2025",
        authors: "Brennan, Weakley, Johnston & Creaby",
        year: 2025,
        title: "Exercise Classification in Resistance Training: A Systematic Review of Technological Approaches",
        source: "Sports Medicine 55(10)",
        url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC12513948/"
    )

    // MARK: Passive readiness (revenue Phase 4, D4)

    /// HRV-guided training prescription outperforms a predefined block in cyclists —
    /// but the guidance rests on a *rolling mean vs baseline*, not a single day.
    public static let javaloyesHRVGuided2019 = Citation(
        id: "javaloyesHRVGuided2019",
        authors: "Javaloyes, Sarabia, Lamberts & Moya-Ramon",
        year: 2019,
        title: "Training Prescription Guided by Heart Rate Variability in Cycling",
        source: "International Journal of Sports Physiology and Performance 14(1)",
        url: "https://pubmed.ncbi.nlm.nih.gov/29809080/"
    )

    /// Individualized endurance training prescription guided by weekly HRV improved
    /// outcomes over predefined training — anchors the HRV-baseline fusion rule.
    public static let vesterinenHRVGuided2016 = Citation(
        id: "vesterinenHRVGuided2016",
        authors: "Vesterinen, Nummela, Heikura, Laine, Hynynen, Botella & Häkkinen",
        year: 2016,
        title: "Individual Endurance Training Prescription with Heart Rate Variability",
        source: "Medicine & Science in Sports & Exercise 48(7)",
        url: "https://pubmed.ncbi.nlm.nih.gov/26909534/"
    )

    /// Review of monitoring training status with HR measures — cautions that resting
    /// HR / HRV are noisy day-to-day and should be read as trends, not single points.
    public static let buchheitMonitoring2014 = Citation(
        id: "buchheitMonitoring2014",
        authors: "Buchheit",
        year: 2014,
        title: "Monitoring training status with HR measures: do all roads lead to Rome?",
        source: "Frontiers in Physiology 5:73",
        url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC3936188/"
    )

    /// Systematic review + meta-analysis: acute sleep loss impairs physical
    /// performance — backs the sleep-debt contribution to the passive signal.
    public static let cravenSleep2022 = Citation(
        id: "cravenSleep2022",
        authors: "Craven, McCartney, Desbrow, Sabapathy, Bellinger, Roberts & Irwin",
        year: 2022,
        title: "Effects of Acute Sleep Loss on Physical Performance: A Systematic and Meta-Analytical Review",
        source: "Sports Medicine 52(11)",
        url: "https://pubmed.ncbi.nlm.nih.gov/35708888/"
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
        zourdosRIR2016, tanakaMaxHR2001, kaufmannThreshold2023, milanovicHIIT2015,
        slothSIT2013, buchheitLaursenHIIT2013, konradStretchROM2024, behmStretching2016,
        lauersenInjuryPrevention2014, fieldFitnessReliability2022, tongPlank2014,
        murlasitsConcurrentSequence2018, currierResistancePrescription2023,
        tabata1996, gibala2006, metcalfeREHIT2012, gunnarsson1020302012,
        brennanExerciseClassification2025,
        seilerPolarized2010,
        javaloyesHRVGuided2019, vesterinenHRVGuided2016, buchheitMonitoring2014,
        cravenSleep2022,
    ]

    public static func citation(forId id: String) -> Citation? {
        all.first { $0.id == id }
    }

    // MARK: - Bibliography (Coach Research Updates)

    /// One-line, user-facing description of *why the coach uses* each citation.
    /// Kept separate from `Citation` so the model stays a pure reference record.
    /// Every id in `all` MUST have an entry here (enforced by `CitationIntegrityTests`).
    public static let usageReasons: [String: String] = [
        "schoenfeld2021": "Loading recommendations — anchors the rep continuum for strength, hypertrophy, and endurance prescriptions.",
        "volumeDoseResponse": "Weekly sets-per-muscle dose-response — backs volume add/trim recommendations and per-part progress.",
        "frequencyMeta": "Spreading weekly volume across ≥2 sessions per week improves per-set quality and recovery.",
        "oneRMEstimation": "Prediction equations for estimated 1RM — backs the e1RM formula picker and assessment retest prompts.",
        "rpeAutoregulation": "RIR-based RPE scale — backs autoregulation for load selection and proximity-to-failure prescriptions.",
        "cooperVo2max": "Cooper 12-minute run field test — backs the VO₂max assessment protocol.",
        "wingateTest": "Wingate anaerobic test — backs the Wingate assessment and SIT/anaerobic training prescriptions.",
        "hiitVo2max": "Aerobic high-intensity intervals improve VO₂max — backs HIIT prescriptions for cardiorespiratory fitness.",
        "rockportWalk": "Rockport 1-mile walk VO₂max estimation — backs the walk assessment protocol.",
        "queensCollegeStep": "Queens College step test — backs the step-test assessment protocol.",
        "krieger2010": "Multi-set training superior to single-set for hypertrophy — backs the multi-set default for built-in programs.",
        "rheaPeriodization": "Periodized training superior to non-periodized — backs periodized program templates and periodization logic.",
        "calatayudBodyweight": "Bodyweight training effective for strength — backs the calisthenics program routine.",
        "channellOlympic": "Olympic lifting for explosive power — backs the Olympic weightlifting program routine.",
        "zourdosDUP": "Daily undulating periodization — backs the DUP program routine.",
        "amirthalingamGVT": "German Volume Training effectiveness — backs the GVT routine and per-session volume warnings.",
        "williamsLinearPeriodization": "Linear periodization effectiveness — backs linear programs (5/3/1) and periodization claims.",
        "tufanoCluster": "Cluster set training — backs the cluster-set program routine.",
        "ekelundActivityMortality2016": "Physical activity attenuates sitting-time mortality risk — backs aerobic-base recommendations and the 150-min floor.",
        "pellandDoseResponse2026": "Resistance training dose-response meta-regression — backs volume personalization and over-MRV trim warnings.",
        "ramosCampoSplit2024": "Full-body vs split routine effects on strength and hypertrophy — backs session-structure choices in the weekly plan.",
        "parejaBlancoRecovery2020": "48-hour same-lift recovery window after training to failure — backs the session eligibility deferral gates.",
        "sawMonitoring2016": "Self-reported measures trump objective monitoring — backs the readiness check-in system, recovery recommendations, and the passive-readiness FUSION rule (self-report wins wherever present; passive signals only fill the gap).",
        "meeusenOvertraining2013": "Overtraining prevention consensus — backs pain/illness safety gates, hard-day streak warnings, and rest-day prescriptions.",
        "schumannConcurrent2022": "Concurrent aerobic + strength compatibility — backs lower-body collision gates and two-a-day timing guidance.",
        "crowleyVO2Intensity2022": "Exercise intensity and VO₂max improvement — backs VO₂-interval session prescriptions.",
        "poonHIIT2024": "HIIT and cardiorespiratory fitness umbrella review — backs HIIT session candidates and prescriptions.",
        "mooreLeisureActivity2012": "Leisure-time activity and mortality — supplementary evidence for aerobic-base recommendations.",
        "aremDoseResponse2015": "Dose-response of physical activity and mortality — supplementary evidence for aerobic-base recommendations.",
        "saintMauriceSteps2020": "Daily step count and mortality — backs the step-health display and step-target guidance.",
        "leeAccelerometer2019": "Step volume/intensity in older women — supplementary evidence for step-health insights.",
        "halsonRecovery2014": "Monitoring training load to understand fatigue — supplementary evidence for recovery-readiness insights.",
        "drewFinchInjury2016": "Training load and injury/illness/soreness relationship — backs warnings about excessive volume and consecutive hard days.",
        "dupuyFatigue2018": "Evidence-based post-exercise recovery techniques — supplementary evidence for recovery-readiness insights.",
        "zourdosRIR2016": "Novel RPE scale measuring repetitions in reserve — backs the strength-intensity prescription pool.",
        "tanakaMaxHR2001": "Age-predicted maximal heart rate — backs threshold/tempo training when HR zones are estimated rather than tested.",
        "seilerPolarized2010": "Training intensity distribution in endurance athletes — backs how the coach reads weekly cardio time spread across HR zones (mostly easy, some hard).",
        "kaufmannThreshold2023": "HRV-derived thresholds for exercise intensity prescription — backs threshold/tempo training prescriptions.",
        "milanovicHIIT2015": "HIIT vs continuous endurance training for VO₂max — supplementary evidence for VO₂-interval prescriptions.",
        "slothSIT2013": "Sprint interval training effects on VO₂max — backs the anaerobic/SIT opt-in prescription.",
        "buchheitLaursenHIIT2013": "HIIT programming: anaerobic energy and neuromuscular load — supplementary evidence for anaerobic training.",
        "konradStretchROM2024": "Chronic stretching effects on range of motion — backs stretch/mobility session candidates.",
        "behmStretching2016": "Acute stretching effects on performance and ROM — supplementary evidence for flexibility recommendations.",
        "lauersenInjuryPrevention2014": "Exercise interventions to prevent sports injuries — cited in Coach's safety-first philosophy (not tied to any single exercise modality).",
        "fieldFitnessReliability2022": "Reliability of field-based fitness tests — backs bodyweight benchmark assessments (push-up, pull-up, squat, hollow hold).",
        "tongPlank2014": "Sport-specific endurance plank test — backs the plank hold assessment protocol.",
        "murlasitsConcurrentSequence2018": "Concurrent strength-endurance training sequence — backs same-day cardio-timing guidance in schedule preferences.",
        "currierResistancePrescription2023": "Bayesian network meta-analysis of resistance training prescription — backs strength-block engine rules.",
        "tabata1996": "Original Tabata protocol study (20 s all-out / 10 s rest) — backs the Tabata interval preset.",
        "gibala2006": "Short-term sprint interval training matching traditional endurance adaptations — backs the Gibala interval preset.",
        "metcalfeREHIT2012": "Reduced-exertion HIIT with 2 × 20 s sprints in a 10-min session — backs the REHIT interval preset.",
        "gunnarsson1020302012": "The 10-20-30 training concept (low/mod/sprint stepping) — backs the 10-20-30 interval preset.",
        "brennanExerciseClassification2025": "Exercise classification in resistance training — backs the \"custom exercises need muscle definitions\" insight.",
        "javaloyesHRVGuided2019": "HRV-guided training prescription — backs reading passive HRV as a rolling-mean-vs-baseline trend, never a single day.",
        "vesterinenHRVGuided2016": "Individualized HRV-guided endurance prescription — backs the passive-readiness baseline fusion with self-report.",
        "buchheitMonitoring2014": "Monitoring training status with HR measures — backs the caution that resting HR / HRV are read as trends, not single points.",
        "cravenSleep2022": "Acute sleep loss impairs physical performance — backs the sleep-debt contribution to the passive readiness signal.",
    ]

    /// Resolve the user-facing "why we use it" line for a citation id, if present.
    public static func usageReason(forId id: String) -> String? {
        usageReasons[id]
    }

    /// All citations, sorted by first author surname (scientific convention). The
    /// `authors` field is always "Surname, Others & Last" so an alphabetical sort
    /// yields correct author-order for every entry.
    public static var bibliography: [Citation] {
        all.sorted { a, b in
            a.authors.localizedCaseInsensitiveCompare(b.authors) == .orderedAscending
        }
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

    // MARK: - Claim-specific citation pools (2026-06-25 evidence upgrade)
    //
    // Each pool serves exactly one `EvidenceClaimCategory`. Splitting the broad
    // `aerobicPool` into these prevents a step-count or mortality study from being
    // cited next to, say, a VO₂-interval prescription. Resolve via
    // `citationPool(for:)`; the integrity tests assert no cross-category leakage.

    /// Health floor for moderate-equivalent aerobic *minutes* (NOT step count).
    public static let activityMinutesHealthPool = CitationPool(id: "activityMinutesHealth", citationIds: [
        "ekelundActivityMortality2016",
        "mooreLeisureActivity2012",
        "aremDoseResponse2015",
    ])

    /// Step-count claims only. Step studies must not back the 150-minute threshold.
    public static let stepsHealthPool = CitationPool(id: "stepsHealth", citationIds: [
        "saintMauriceSteps2020",
        "leeAccelerometer2019",
    ])

    /// Aerobic *base* training (easy/moderate continuous work). Shares the activity
    /// health references; never cites step-only or high-intensity studies.
    public static let aerobicBasePool = CitationPool(id: "aerobicBase", citationIds: [
        "ekelundActivityMortality2016",
        "mooreLeisureActivity2012",
        "aremDoseResponse2015",
    ])

    public static let vo2TrainingPool = CitationPool(id: "vo2Training", citationIds: [
        "crowleyVO2Intensity2022",
        "poonHIIT2024",
        "milanovicHIIT2015",
        "hiitVo2max",
    ])

    public static let thresholdTrainingPool = CitationPool(id: "thresholdTraining", citationIds: [
        "kaufmannThreshold2023",
    ])

    public static let anaerobicTrainingPool = CitationPool(id: "anaerobicTraining", citationIds: [
        "wingateTest",
        "slothSIT2013",
        "buchheitLaursenHIIT2013",
    ])

    public static let strengthFrequencyPool = CitationPool(id: "strengthFrequency", citationIds: [
        "frequencyMeta",
    ])

    public static let strengthVolumePool = CitationPool(id: "strengthVolume", citationIds: [
        "volumeDoseResponse",
        "pellandDoseResponse2026",
    ])

    public static let strengthIntensityPool = CitationPool(id: "strengthIntensity", citationIds: [
        "schoenfeld2021",
        "currierResistancePrescription2023",
        "zourdosRIR2016",
        "rpeAutoregulation",
    ])

    public static let periodizationPool = CitationPool(id: "periodization", citationIds: [
        "williamsLinearPeriodization",
        "rheaPeriodization",
    ])

    public static let flexibilityROMPool = CitationPool(id: "flexibilityROM", citationIds: [
        "konradStretchROM2024",
        "behmStretching2016",
    ])

    public static let recoveryMonitoringPool = CitationPool(id: "recoveryMonitoring", citationIds: [
        "halsonRecovery2014",
        "sawMonitoring2016",
        "dupuyFatigue2018",
        "meeusenOvertraining2013",
        "drewFinchInjury2016",
        "javaloyesHRVGuided2019",
        "vesterinenHRVGuided2016",
        "buchheitMonitoring2014",
        "cravenSleep2022",
    ])

    public static let concurrentTrainingPool = CitationPool(id: "concurrentTraining", citationIds: [
        "schumannConcurrent2022",
    ])

    public static let fieldTestValidityPool = CitationPool(id: "fieldTestValidity", citationIds: [
        "oneRMEstimation",
        "cooperVo2max",
        "rockportWalk",
        "queensCollegeStep",
        "wingateTest",
        "tongPlank2014",
        "fieldFitnessReliability2022",
    ])

    /// Schedule-preference citations: strength frequency, concurrent-training
    /// compatibility, recovery monitoring, and aerobic health floor.
    public static let schedulePreferencePool = CitationPool(id: "schedulePreference", citationIds: [
        "frequencyMeta",
        "pellandDoseResponse2026",
        "schumannConcurrent2022",
        "sawMonitoring2016",
        "halsonRecovery2014",
        "murlasitsConcurrentSequence2018",
    ])

    /// Public-health aerobic floor (150 min moderate-equivalent). Kept in a separate
    /// pool so it never backs a training recommendation directly; this pool cites the
    /// same peer-reviewed evidence as activityMinutesHealthPool.
    public static let publicHealthGuidelinePool = CitationPool(id: "publicHealthGuideline", citationIds: [
        "ekelundActivityMortality2016",
    ])

    /// Session-structure choices (full-body vs split). Backs the coach's transparent
    /// explanation of *why* it built a full-body or focused session for a given day.
    public static let sessionStructurePool = CitationPool(id: "sessionStructure", citationIds: [
        "ramosCampoSplit2024",
    ])

    /// Exercise classification citations — backs the "custom exercises need muscle
    /// definitions" insight.
    public static let exerciseDefinitionPool = CitationPool(id: "exerciseDefinition", citationIds: [
        "brennanExerciseClassification2025",
    ])

    /// Exercise-based injury-prevention evidence. Backs the coach's safety-first
    /// philosophy copy only — deliberately NOT tied to any flexibility/ROM claim
    /// (Lauersen shows strength/multi-component programs, not stretching, reduce
    /// injury risk). Not resolvable from any `EvidenceClaimCategory`.
    public static let injuryPreventionPool = CitationPool(id: "injuryPrevention", citationIds: [
        "lauersenInjuryPrevention2014",
    ])

    /// The single citation pool that may support a given claim category. Total over
    /// `EvidenceClaimCategory`, so every typed claim has a resolvable pool.
    public static func citationPool(for category: EvidenceClaimCategory) -> CitationPool {
        switch category {
        case .activityMinutesHealth: return activityMinutesHealthPool
        case .stepsHealth: return stepsHealthPool
        case .strengthFrequency: return strengthFrequencyPool
        case .strengthVolume: return strengthVolumePool
        case .strengthIntensity: return strengthIntensityPool
        case .periodization: return periodizationPool
        case .aerobicBase: return aerobicBasePool
        case .vo2Training: return vo2TrainingPool
        case .thresholdTraining: return thresholdTrainingPool
        case .anaerobicTraining: return anaerobicTrainingPool
        case .flexibilityROM: return flexibilityROMPool
        case .recoveryMonitoring: return recoveryMonitoringPool
        case .concurrentTraining: return concurrentTrainingPool
        case .fieldTestValidity: return fieldTestValidityPool
        case .schedulePreference: return schedulePreferencePool
        case .publicHealthGuideline: return publicHealthGuidelinePool
        case .sessionStructure: return sessionStructurePool
        }
    }
}
