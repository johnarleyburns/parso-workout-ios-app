import Foundation

/// Catalog provenance is separate from coaching-prescription studies.
/// Clinical guides identify movements; vendor material establishes equipment
/// variants only. A zero year means the page is undated.
public enum ExerciseCatalogEvidence {
    public static let citations: [Citation] = [
        Citation(
            id: "catalog.aaos_ankle_conditioning", authors: "American Academy of Orthopaedic Surgeons", year: 0,
            title: "Foot and Ankle Conditioning Program",
            source: "Clinical exercise guide",
            url: "https://www.orthoinfo.org/recovery/foot-and-ankle-conditioning-program/"
        ),
        Citation(
            id: "catalog.nhs_toe_raise", authors: "South Tees Hospitals NHS Foundation Trust", year: 2022,
            title: "Strength and balance exercise programme for falls prevention",
            source: "Clinical exercise guide",
            url: "https://www.southtees.nhs.uk/resources/strength-and-balance-exercise-programme-for-falls-prevention/"
        ),
        Citation(
            id: "catalog.nhs_seated_toe_raise", authors: "Kent Community Health NHS Foundation Trust", year: 0,
            title: "Lower limb strengthening activities",
            source: "Clinical exercise guide",
            url: "https://www.kentcht.nhs.uk/leaflet/lower-limb-strengthening-activities/"
        ),
        Citation(
            id: "catalog.nhs_strength_balance_toe_raise", authors: "NHS inform", year: 0,
            title: "Strength and balance exercises",
            source: "Clinical exercise guide",
            url: "https://www.nhsinform.scot/healthy-living/preventing-falls/keeping-well/strength-and-balance-exercises"
        ),
        Citation(
            id: "catalog.tib_bar_manufacturer", authors: "Tib Bar Bros", year: 0,
            title: "Tib Bar – Tibialis Trainer",
            source: "Manufacturer demonstration; exercise identity only",
            url: "https://tib-bar.com/products/tib-bar"
        ),
        Citation(
            id: "catalog.osu_iliopsoas_progression", authors: "Ohio State University Wexner Medical Center", year: 2020,
            title: "Gluteus Medius Repair: Appendix A, Psoas Progression",
            source: "Clinical exercise progression",
            url: "https://medicine.osu.edu/-/media/files/medicine/departments/sports-medicine/medical-professionals/hip/glute-med-repair-2020.pdf?hash=61FBA1E505B6173CD4D4C753FC8E8A8484725F81&la=en"
        ),
        Citation(
            id: "catalog.cuh_hip_flexion", authors: "Cambridge University Hospitals NHS Foundation Trust", year: 0,
            title: "Hip strengthening exercises",
            source: "Clinical exercise guide",
            url: "https://www.cuh.nhs.uk/patient-information/hip-strengthening-exercises/"
        ),
        Citation(
            id: "catalog.uw_seated_hip_flexion", authors: "University of Washington Medical Center", year: 2021,
            title: "Physical Therapy Before and After Your ACL Surgery: Seated Hip Flexion",
            source: "Clinical exercise guide",
            url: "https://healthonline.washington.edu/sites/default/files/record_pdfs/Physical-Therapy-Before-After-Your-ACL-Surgery-CH.pdf"
        ),
        Citation(
            id: "catalog.nhs_resisted_neck_rotation", authors: "DynamicHealth NHS", year: 0,
            title: "Neck pain: Resisted neck exercises",
            source: "Clinical exercise guide",
            url: "https://www.dynamichealth.nhs.uk/help-and-advice/neck-pain/"
        ),
        Citation(
            id: "catalog.aaos_rotator_cuff_conditioning", authors: "American Academy of Orthopaedic Surgeons", year: 0,
            title: "Rotator Cuff and Shoulder Conditioning Program",
            source: "Clinical exercise guide",
            url: "https://www.orthoinfo.org/bodypart/shoulder/rotator-cuff-and-shoulder-conditioning-program/?webid=24DCE756"
        ),
        Citation(
            id: "catalog.andersson_hip_flexor_emg_1997", authors: "Andersson et al.", year: 1997,
            title: "Abdominal and hip flexor muscle activation during various training exercises",
            source: "European Journal of Applied Physiology",
            url: "https://pubmed.ncbi.nlm.nih.gov/9118976/"
        ),
        Citation(
            id: "catalog.juker_psoas_emg_1998", authors: "Juker, McGill, Kropf & Steffen", year: 1998,
            title: "Quantitative intramuscular myoelectric activity of lumbar portions of psoas and the abdominal wall during a wide variety of tasks",
            source: "Medicine & Science in Sports & Exercise",
            url: "https://pubmed.ncbi.nlm.nih.gov/9502361/"
        ),
        Citation(
            id: "catalog.reinold_supraspinatus_emg_2007", authors: "Reinold et al.", year: 2007,
            title: "Electromyographic analysis of the supraspinatus and deltoid muscles during 3 common rehabilitation exercises",
            source: "Journal of Athletic Training",
            url: "https://pubmed.ncbi.nlm.nih.gov/18174934/"
        ),
        Citation(
            id: "catalog.kim_split_squat_ankle_emg_2017", authors: "Kim et al.", year: 2017,
            title: "Comparison of Activities of Tibialis Anterior, Peroneus Longus, and Tibialis Posterior Muscles according to Lunge Squats and Bulgarian Split Squats in a Healthy Population",
            source: "Journal of KEMA",
            url: "https://www.jkema.org/archive/view_article?pid=jkema-1-1-26"
        ),
        Citation(
            id: "catalog.neck_shrug_training_1997", authors: "Okamoto, Isaka & Fukugawa", year: 1997,
            title: "Effects of neck muscle training and detraining on neck muscle strength",
            source: "Japanese Journal of Physical Fitness and Sports Medicine",
            url: "https://www.jstage.jst.go.jp/article/jspfsm1949/46/2/46_2_201/_article/-char/en"
        ),
    ]

    public static let usageReasons: [String: String] = [
        "catalog.aaos_ankle_conditioning": "Documents band-resisted dorsiflexion and identifies anterior tibialis; supports exercise selection, not a measured set-credit fraction.",
        "catalog.nhs_toe_raise": "Documents lifting the forefoot while retaining heel contact; supports the bodyweight toe-raise movement.",
        "catalog.nhs_seated_toe_raise": "Documents seated toe lifts with heels down; supports toe-raise terminology and accessible progression.",
        "catalog.nhs_strength_balance_toe_raise": "Documents toe raises; corroborates bodyweight dorsiflexion as a distinct exercise from calf raises.",
        "catalog.tib_bar_manufacturer": "Documents bilateral and unilateral tib-bar equipment and seated dorsiflexion technique only; commercial injury-prevention claims are not adopted.",
        "catalog.osu_iliopsoas_progression": "Documents supine short-lever, seated, and standing resisted hip flexion; supports distinct positions, not transfer of postoperative dosage to general training.",
        "catalog.cuh_hip_flexion": "Documents supported standing hip flexion with the knee bent and a hold; supports the standing hip-flexion hold.",
        "catalog.uw_seated_hip_flexion": "Documents seated bent-knee hip flexion as distinct from a straight-leg raise; supports exercise identity only.",
        "catalog.nhs_resisted_neck_rotation": "Documents hand-resisted cervical rotation, flexion and side flexion; rotation is a distinct addition, while existing flexion/side records retain their IDs.",
        "catalog.aaos_rotator_cuff_conditioning": "Documents 90-degree-abducted external rotation, supine rotation and side-lying internal/external rotation. Existing side-lying external rotation is retained with aliases.",
        "catalog.andersson_hip_flexor_emg_1997": "Fine-wire iliacus evidence supports hip-flexor involvement during hip-flexion sit-ups and leg lifts, without extending the claim to every curl-up.",
        "catalog.juker_psoas_emg_1998": "Sit-ups recruited psoas more than curl-ups. Supports exact full-sit-up indirect hip-flexor roles, not a measured 0.5 hypertrophy equivalence or general lifting credit.",
        "catalog.reinold_supraspinatus_emg_2007": "Fine-wire EMG supports supraspinatus involvement in full-can scaption and prone horizontal abduction with external rotation. The incline reverse-fly mapping is a medium-confidence extrapolation; 0.5 remains the DB++ accounting convention.",
        "catalog.kim_split_squat_ankle_emg_2017": "Measures ankle-stability activation during held squat postures; insufficient to assign 0.5 tibialis sets to ordinary squats or lunges.",
        "catalog.neck_shrug_training_1997": "Narrow-grip shrug intervention suggests neck-strength transfer in a specific protocol; does not establish an independent neck hypertrophy dose for all shrug variants, so no blanket 0.5 credit is awarded.",
    ]
}
