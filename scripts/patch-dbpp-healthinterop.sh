#!/usr/bin/env bash
set -euo pipefail

# DB++ 1.17.0 introduced HealthKit interop with declarations that are one
# macOS SDK generation too broad and continuation closures whose result type
# Swift 6 cannot infer. Keep the exact upstream pin; patch only the generated
# checkout used by this build until the upstream package carries the fixes.

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
roots=(
  "${repo_root}/CadenceCore/.build/checkouts"
  "${repo_root}/.build"
  "${HOME}/Library/Developer/Xcode/DerivedData"
)
if [[ $# -gt 0 ]]; then
  roots+=("$@")
fi
files=()
for root in "${roots[@]}"; do
  if [[ -d "$root" ]]; then
    while IFS= read -r file; do
      files+=("$file")
    done < <(find "$root" -path '*/free-exercise-db-plusplus/packages/swift/FreeExerciseDBPlusPlus/Sources/FreeExerciseDBPlusPlus/HealthInterop.swift' -type f -print)
  fi
done

if [[ ${#files[@]} -eq 0 ]]; then
  echo "DB++ HealthInterop patch: no resolved 1.17.0 checkout found" >&2
  exit 0
fi

for file in "${files[@]}"; do
  if ! grep -q 'class HealthKitAdapter' "$file"; then
    echo "DB++ HealthInterop patch: unexpected source file: $file" >&2
    exit 1
  fi

  perl -0pi -e 's/\@available\(iOS 15\.0, macOS 12\.0, watchOS 8\.0, \*\)/\@available(iOS 15.0, macOS 13.0, watchOS 8.0, *)/' "$file"
  perl -0pi -e 's/(let workoutType = HKObjectType\.workoutType\(\)\n\s*)try await withCheckedThrowingContinuation \{ continuation in/$1try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in/' "$file"
  perl -0pi -e 's/(public func importCanonicalWorkouts\(\) async throws -> \[Data\] \{\n\s*)try await withCheckedThrowingContinuation \{ continuation in/$1try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Data], Error>) in/' "$file"
  perl -0pi -e 's/(private func begin\(_ builder: HKWorkoutBuilder, start: Date\) async throws \{\n\s*)try await withCheckedThrowingContinuation \{ continuation in/$1try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in/' "$file"
  perl -0pi -e 's/(private func addMetadata\(_ builder: HKWorkoutBuilder, metadata: \[String: Any\]\) async throws \{\n\s*)try await withCheckedThrowingContinuation \{ continuation in/$1try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in/' "$file"
  perl -0pi -e 's/(private func end\(_ builder: HKWorkoutBuilder, end: Date\) async throws \{\n\s*)try await withCheckedThrowingContinuation \{ continuation in/$1try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in/' "$file"
  perl -0pi -e 's/(private func finish\(_ builder: HKWorkoutBuilder\) async throws -> HKWorkout \{\n\s*)try await withCheckedThrowingContinuation \{ continuation in/$1try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKWorkout, Error>) in/' "$file"
  perl -0pi -e 's/let end: Date =/let endDate: Date =/; s/try await end\(builder, end: end\)/try await end(builder, end: endDate)/' "$file"

  if grep -q 'macOS 12.0' "$file" || grep -q 'let end: Date' "$file"; then
    echo "DB++ HealthInterop patch: failed to apply compatibility edits: $file" >&2
    exit 1
  fi
  echo "DB++ HealthInterop patch: patched $file"
done
