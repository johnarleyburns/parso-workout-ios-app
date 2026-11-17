# Shared module extraction progress

Work is committed locally on the existing PR branch. Do not push or update the remote PR until the owner authorizes publication.

| Phase | Implementation | Verification |
| --- | --- | --- |
| 1. Garmin portability | One Garmin bridge moved to CadencePortability; phone-only product link; existing FIT tests moved intact. Canonical mapping exposed with package access. | Manifest/Xcode boundary regression failed before extraction and passes after. Swift syntax and import boundary guards pass. Apple-platform FIT execution/builds remain unavailable on this Linux host. |
| 2. Widget contracts | Pending | Pending |
| 3. Shared workout / phone separation | Pending | Pending |
| 4. Coaching isolation | Pending | Pending |

Persistent model definitions, schema membership and ActivityKit attributes must retain their defining modules. Every policy/mapping has one production definition. Apple-platform builds, FIT round trips, old-store upgrades, widgets/Live Activities, and offline Watch device checks remain release gates; static graph checks do not substitute for them.
