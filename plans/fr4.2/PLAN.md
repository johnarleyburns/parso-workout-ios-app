# FR-4.2 — Local-first storage as source of truth

> Local-first storage (SwiftData/Core Data) as the source of truth for the rich
> strength model HealthKit cannot represent (exercise → sets → reps → weight).

## Design
- Already realized in the foundation: `CadenceStore` builds a SwiftData
  `ModelContainer`; `WorkoutRepository` is the single source of truth for
  exercise → session → set. HealthKit only ever receives summaries (FR-4.3).
- The store runs fully local by default (`cloudKitDatabase: .none`), opted into
  CloudKit only when the user enables sync (FR-4.5).

## Mockups
N/A (architecture).

## Implementation
- `Models.swift`, `Store.swift`, `WorkoutRepository.swift`.

## Automated testing
- **Integration:** the entire `WorkoutRepositoryTests` suite exercises the local
  store (CRUD, PR, last-time, export/import) against an in-memory container.
