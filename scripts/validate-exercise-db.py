#!/usr/bin/env python3
"""Validate a free-exercise-db++ snapshot before it is vendored.

The bundled document is the source of truth for muscle roles, weekly volume
credit, and every muscle-attribution citation the app shows, so a malformed or
schema-shifted refresh must never silently replace it. Run by
It is also usable directly when validating a downloaded or generated artifact:

    python3 scripts/validate-exercise-db.py <path-to-json>

Exits non-zero with an explanation on any violation.
"""
import json
import sys

# The ontology `MuscleGroup` is generated from. A refresh that changes it is a
# breaking change and must be handled deliberately, not absorbed silently.
EXPECTED_ONTOLOGY = {
    "abdominals", "abductors", "adductors", "biceps", "calves", "chest",
    "forearms", "glutes", "hamstrings", "lats", "lower_back", "middle_back",
    "neck", "quadriceps", "shoulders", "traps", "triceps", "tibialis",
    "rotator_cuff", "hip_flexors",
}


def fail(message):
    print("ERROR: %s" % message)
    sys.exit(1)


def main(path):
    try:
        with open(path) as handle:
            doc = json.load(handle)
    except Exception as error:  # noqa: BLE001 - any parse failure is fatal here
        fail("not valid JSON (%s)" % error)

    for key in ("metadata", "exercises"):
        if key not in doc:
            fail("missing top-level key %r" % key)

    meta = doc["metadata"]
    exercises = doc["exercises"]

    if meta.get("completeness") != "full":
        fail("completeness is %r, expected 'full'" % meta.get("completeness"))

    if meta.get("outputExerciseCount") != len(exercises):
        fail("outputExerciseCount %r does not match %d exercises"
             % (meta.get("outputExerciseCount"), len(exercises)))

    ontology = set(meta.get("muscleOntology") or [])
    if ontology != EXPECTED_ONTOLOGY:
        fail("muscleOntology changed — added %s, removed %s. MuscleGroup must be "
             "updated deliberately before this snapshot can be vendored."
             % (sorted(ontology - EXPECTED_ONTOLOGY),
                sorted(EXPECTED_ONTOLOGY - ontology)))

    credits = meta.get("setCredits") or {}
    for role in ("direct", "indirect", "stabilizer"):
        if not isinstance(credits.get(role), (int, float)):
            fail("setCredits.%s is missing or not a number" % role)

    references = (meta.get("evidence") or {}).get("references") or {}
    patterns = (meta.get("evidence") or {}).get("patterns") or {}
    for ref_id, ref in references.items():
        if not ref.get("url"):
            fail("evidence reference %r has no url" % ref_id)
    for pattern_id, pattern in patterns.items():
        if not pattern.get("summary"):
            fail("evidence pattern %r has no summary" % pattern_id)
        for ref_id in pattern.get("references") or []:
            if ref_id not in references:
                fail("pattern %r cites unknown reference %r" % (pattern_id, ref_id))

    for key, entry in exercises.items():
        annotation = entry.get("annotation") or {}
        source = entry.get("source") or {}
        if entry.get("exerciseId") != key:
            fail("exercise %r has mismatched exerciseId %r"
                 % (key, entry.get("exerciseId")))
        if not source.get("name"):
            fail("exercise %r has no source name" % key)
        for role in ("direct", "indirect", "stabilizers"):
            unknown = set(annotation.get(role) or []) - ontology
            if unknown:
                fail("exercise %r has out-of-ontology %s muscles %s"
                     % (key, role, sorted(unknown)))
        if annotation.get("volumeEligible") and not annotation.get("direct"):
            fail("exercise %r is volume-eligible with no direct muscles" % key)
        for ref in annotation.get("evidenceRefs") or []:
            if not ref.startswith("pattern:"):
                fail("exercise %r has unexpected evidence ref %r" % (key, ref))
            if ref.split(":", 1)[1] not in patterns:
                fail("exercise %r cites unknown pattern %r" % (key, ref))

    eligible = sum(1 for e in exercises.values()
                   if (e.get("annotation") or {}).get("volumeEligible"))
    print("OK: %d exercises (%d volume-eligible), schema %s, converter %s, "
          "generated %s"
          % (len(exercises), eligible, meta.get("schemaVersion"),
             meta.get("converterVersion"), meta.get("generatedAt")))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: validate-exercise-db.py <path-to-json>")
        sys.exit(2)
    main(sys.argv[1])
