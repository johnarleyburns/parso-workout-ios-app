# Cladiron — in-workout strength entry redesign (handoff)

**Reference mockup: `workout_entry_mockup.html`** (open it). The redesign turns the
per-exercise set list into a columnar tap-to-log table and removes the crowded
free-floating editor. The sections below map to that mockup.

Scope: mostly one file — `Cadence/Cadence/Features/Train/SessionView.swift`, plus a
small dialog change to the shared `Cadence/Cadence/Features/Shared/WorkoutControlBar.swift`
(§A9). No engine, model, or repository changes; the existing
`WorkoutRepository.addSet/updateSet/deleteSet`, `recordInlineSet`, `addSet(...)`,
`nextPerson()`, and the cool-down flow (`coolDownConfirm` → `GuidedPhaseOverlay`)
are reused as-is. There are two options — **Option A** is the full columnar
redesign (recommended), and it now also covers training partners (§A8) and the
End/cool-down confirmation (§A9); **Option B** at the end is a 10-minute fix for
just the wrapping if you want to ship that first.

## Why the buttons wrap today

`inlineEditor(for:)` packs a second `HStack` with the alt-weight text, a `BW`
toggle, a partner `Picker`, a `PR` label, a delete button, `Cancel`, and `Record`
all on one line. The card is nested two paddings deep (~256–326pt wide), the
weight field and unit picker take fixed `.frame(width: 80)`/`.frame(width: 90)`,
and the text buttons have no `lineLimit`. When the row runs out of width, SwiftUI
**wraps** `Text` rather than truncating it — so "Cancel"/"Record" break one
character or word per line. The fix is to stop putting many controls on one row.

---

## Option A — columnar tap-to-log (recommended)

Each set is a row in a fixed-column table: **Set · Prev · Weight · Reps · ✓**.
The set being entered is a highlighted row with real input cells and one large
checkmark that logs it (and starts rest). Secondary controls move to a per-row
long-press menu.

### A0. Column metrics + header

```swift
private enum SetCol {
    static let num: CGFloat = 26
    static let prev: CGFloat = 50
    static let reps: CGFloat = 46
    static let check: CGFloat = 34
    static let gap: CGFloat = 7
}

private var setColumnHeader: some View {
    HStack(spacing: SetCol.gap) {
        Text("Set").frame(width: SetCol.num, alignment: .leading)
        Text("Prev").frame(width: SetCol.prev, alignment: .leading)
        Text("Weight (\(settings.unit.abbreviation))").frame(maxWidth: .infinity, alignment: .center)
        Text("Reps").frame(width: SetCol.reps, alignment: .center)
        Color.clear.frame(width: SetCol.check)
    }
    .font(.caption2).textCase(.uppercase).foregroundStyle(.tertiary)
    .padding(.horizontal, 2)
}
```

### A1. Set-number badge (warm-ups show "W")

```swift
private func setIndexBadge(_ label: String, isWarmup: Bool) -> some View {
    Group {
        if isWarmup {
            Text("W").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                .frame(width: 22, height: 22).background(.orange.opacity(0.15), in: Circle())
        } else {
            Text(label).font(.subheadline.weight(.medium)).monospacedDigit()
        }
    }
    .frame(width: SetCol.num, alignment: .leading)
}
```

### A2. Completed set row (replaces the old `setRow`)

```swift
private func completedSetRow(_ set: SetEntry, number: String, exercise: Exercise) -> some View {
    HStack(spacing: SetCol.gap) {
        setIndexBadge(number, isWarmup: set.isWarmup)

        Text(previousReference(for: exercise, number: number))
            .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            .frame(width: SetCol.prev, alignment: .leading)

        // Tap weight or reps to edit the set inline (re-opens it as the active row).
        Button { openInlineEditor(for: exercise, editing: set) } label: {
            Text(Format.weightValue(set.weight, unit: settings.unit))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)

        Button { openInlineEditor(for: exercise, editing: set) } label: {
            Text("\(set.reps)").monospacedDigit().frame(width: SetCol.reps)
        }
        .buttonStyle(.plain)

        // Check column: PR → trophy, otherwise a filled green check.
        Group {
            if isAllTimePR(set, exercise: exercise) {
                Image(systemName: "trophy.fill").foregroundStyle(.orange)
                    .accessibilityIdentifier("set.prBadge")
            } else {
                Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
            }
        }
        .frame(width: SetCol.check)
    }
    .frame(minHeight: 44)
    .contentShape(Rectangle())
    .contextMenu { rowMenu(for: set, exercise: exercise) }
    .accessibilityIdentifier("set.row.\(exercise.name).\(number)")
}
```

### A3. Active entry row (replaces the free-floating `inlineEditor`)

The crowded second `HStack` is gone. Weight and reps are input cells; one
checkmark logs the set via the existing `recordInlineSet`. Alt-unit preview, the
bodyweight toggle, and Cancel sit on a quiet secondary line under the inputs.

```swift
@ViewBuilder
private func activeSetRow(for exercise: Exercise) -> some View {
    let parsed = Double(inlineWeight) ?? 0
    let kg = WorkoutMath.canonical(parsed, from: settings.unit)
    let altUnit: MeasurementUnitPreference = settings.unit == .kilograms ? .pounds : .kilograms
    let canSave = inlineReps > 0 && (inlineBodyweight || !inlineWeight.isEmpty)
    let number = String(workingNumber(for: exercise))   // next working-set number

    VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: SetCol.gap) {
            setIndexBadge(number, isWarmup: false)

            Button {
                if let (w, r) = previousValues(for: exercise, number: number) {
                    inlineWeight = Format.weightValue(w, unit: settings.unit); inlineReps = r
                }
            } label: {
                Text(previousReference(for: exercise, number: number))
                    .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    .frame(width: SetCol.prev, alignment: .leading)
            }
            .buttonStyle(.plain)

            TextField("0", text: $inlineWeight)
                .keyboardType(.decimalPad).focused($weightFocused)
                .multilineTextAlignment(.center).monospacedDigit()
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .stroke(weightFocused ? Color.accentColor : Color(.separator),
                            lineWidth: weightFocused ? 1.5 : 0.5))
                .accessibilityIdentifier("inline.weight")

            TextField("0", value: $inlineReps, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center).monospacedDigit()
                .frame(width: SetCol.reps, minHeight: 36)
                .background(.background, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator), lineWidth: 0.5))
                .accessibilityIdentifier("inline.reps")

            Button { recordInlineSet(for: exercise) } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title).foregroundStyle(canSave ? .green : Color(.tertiaryLabel))
            }
            .buttonStyle(.plain).disabled(!canSave)
            .frame(width: SetCol.check)
            .accessibilityIdentifier("inline.save")
        }

        HStack(spacing: 10) {
            if parsed > 0 {
                Text("\u{2248} \(Format.weightValue(kg, unit: altUnit)) \(altUnit.abbreviation)")
                    .font(.caption2).foregroundStyle(.secondary)
                    .accessibilityIdentifier("inline.alt")
            }
            if isBodyweight(exercise) {
                Toggle("Bodyweight", isOn: $inlineBodyweight)
                    .toggleStyle(.button).controlSize(.mini)
                    .accessibilityIdentifier("inline.bodyweight")
            }
            Spacer()
            Button("Cancel") { closeInlineEditor() }
                .font(.caption).accessibilityIdentifier("inline.cancel")
        }
        .padding(.leading, SetCol.num + SetCol.gap)
    }
    .padding(8)
    .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
}
```

Note: `recordInlineSet` converts with `inlineUnit`, and `openInlineEditor` sets
`inlineUnit = settings.unit`, so entry stays correct. The per-set `kg`/`lb`
segmented control is removed (one workout unit); offer a per-set override in the
row menu only if you want it.

### A4. Per-row menu — where warm-up / bodyweight / partner / delete now live

`swipeActions` is a `List`-only modifier; these rows are inside a `ScrollView`, so
the current swipe-to-delete never fires. Use `contextMenu` (works anywhere):

```swift
@ViewBuilder
private func rowMenu(for set: SetEntry, exercise: Exercise) -> some View {
    Button {
        try? WorkoutRepository.updateSet(set, isWarmup: !set.isWarmup, in: context)
    } label: {
        Label(set.isWarmup ? "Mark as working set" : "Mark as warm-up",
              systemImage: set.isWarmup ? "flame.fill" : "flame")
    }
    if isBodyweight(exercise) {
        Button {
            try? WorkoutRepository.updateSet(set, usesBodyweight: !set.usesBodyweight, in: context)
        } label: {
            Label(set.usesBodyweight ? "Remove bodyweight" : "Mark bodyweight",
                  systemImage: "figure.stand")
        }
    }
    if hasPartners {
        Menu {
            Button("Me") { set.performedBy = nil; try? context.save() }
            ForEach(roster.filter { !$0.isMe }) { p in
                Button(p.name) { set.performedBy = p; try? context.save() }
            }
        } label: { Label("Performed by", systemImage: "person") }
    }
    Divider()
    Button(role: .destructive) {
        try? WorkoutRepository.deleteSet(set, in: context)
    } label: { Label("Delete set", systemImage: "trash") }
}
```

### A5. Pending planned row (columnar; replaces the old `pendingRow`)

```swift
private func pendingRow(for exercise: Exercise, number: String, reps: Int) -> some View {
    Button { openInlineEditor(for: exercise, repsOverride: reps) } label: {
        HStack(spacing: SetCol.gap) {
            setIndexBadge(number, isWarmup: false).foregroundStyle(.tertiary)
            Text(previousReference(for: exercise, number: number))
                .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                .frame(width: SetCol.prev, alignment: .leading)
            Text("\(reps) reps").font(.subheadline).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
            Color.clear.frame(width: SetCol.reps)
            Image(systemName: "plus.circle").foregroundStyle(.tint).frame(width: SetCol.check)
        }
        .frame(minHeight: 44).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("set.pending.\(exercise.name).\(number)")
}
```

### A6. `exerciseCard` assembled

```swift
@ViewBuilder
private func exerciseCard(_ exercise: Exercise) -> some View {
    let sets = session.orderedSets.filter { $0.exercise?.id == exercise.id }
    let pending = max(0, plannedSetCount(for: exercise.name) - sets.count)
    let isActive = inlineExerciseID == exercise.id

    VStack(alignment: .leading, spacing: 10) {
        HStack {
            Text(exercise.name).font(.headline)
                .accessibilityIdentifier("exerciseCard.\(exercise.name)")
            Spacer()
            Menu {
                Button(role: .destructive) { exerciseToRemove = exercise } label: {
                    Label("Remove exercise", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis").font(.headline)
                    .foregroundStyle(.secondary).frame(width: 32, height: 32)
            }
            .accessibilityIdentifier("exercise.menu.\(exercise.name)")
        }
        contextLine(for: exercise)

        if !sets.isEmpty || isActive || pending > 0 { setColumnHeader }

        let numbers = workingNumbers(sets)   // [SetEntry.id : "1"/"2"/… , warmups -> ""]
        ForEach(Array(sets.enumerated()), id: \.element.id) { idx, set in
            completedSetRow(set, number: numbers[set.id] ?? "", exercise: exercise)
            if idx < sets.count - 1 || isActive || pending > 0 {
                Divider()
            }
        }

        if isActive { activeSetRow(for: exercise) }

        ForEach(0..<pending, id: \.self) { offset in
            let n = workingNumber(for: exercise, extra: offset)
            pendingRow(for: exercise, number: String(n),
                       reps: plannedReps(for: exercise, setIndex: sets.count + offset))
        }

        if !isActive {
            HStack(spacing: 10) {
                Button { openInlineEditor(for: exercise) } label: {
                    Label("Add set", systemImage: "plus").frame(maxWidth: .infinity).lineLimit(1)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("set.add.\(exercise.name)")

                if let last = sets.last {
                    Button {
                        addSet(to: exercise, weightKg: last.weight, reps: last.reps, rpe: last.rpe,
                               isWarmup: last.isWarmup, usesBodyweight: last.usesBodyweight, note: nil)
                    } label: {
                        Label("Repeat", systemImage: "arrow.clockwise").frame(maxWidth: .infinity).lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("set.repeat.\(exercise.name)")
                }
            }
            .controlSize(.regular)
            .padding(.top, 2)
        }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
}
```

### A7. Small helpers to add

- `workingNumbers(_ sets:) -> [UUID: String]` — assigns "1","2",… to non-warm-up
  sets in order; warm-ups map to "" (badge shows "W"). `workingNumber(for:extra:)`
  returns the next working number (+`extra` for pending rows).
- `previousReference(for:number:) -> String` — from
  `WorkoutRepository.lastTimeSets(for:excluding:)`, the prior session's set at that
  position formatted compactly, e.g. "60×8"; "" when none.
- `previousValues(for:number:) -> (Double, Int)?` — the same prior set's
  `(weightKg, reps)` for tap-to-prefill.

### Delete these

The old `setRow(_:index:exercise:)`, `inlineEditor(for:)`, and
`pendingRow(index:reps:)`. Keep every `@State` (`inlineWeight`, `inlineReps`,
`inlineUnit`, `inlineBodyweight`, `inlinePerformedByID`, `weightFocused`, …),
`openInlineEditor`, `closeInlineEditor`, `recordInlineSet`, and `addSet` — they
already do the right thing.

### A8 · Partners — alternate by set

Your partner workflow is first-class here, not buried in a menu. The
`partnerBar` at the top of `body` stays exactly as-is ("With: Me · Alex +").
Three additions wire it into the columnar rows; the engine already does the
rotation (`nextPerson()` returns whoever has gone longest without a set) and the
PR rule (a partner's set never earns the owner's PR).

**1. A per-person colour + chip.** Colour-code each person by a stable hash of
their id so the same partner is always the same colour across the session.

```swift
private func personColor(_ p: Person?) -> Color {
    guard let p, !p.isMe else { return .accentColor }   // "Me" = app tint
    let palette: [Color] = [.purple, .teal, .pink, .indigo, .orange, .mint]
    return palette[abs(p.id.hashValue) % palette.count]
}

private func performerChip(_ p: Person?) -> some View {
    let label = (p?.isMe ?? true) ? "M" : String((p?.name ?? "?").prefix(1)).uppercased()
    return Text(label)
        .font(.caption2.weight(.semibold)).foregroundStyle(.white)
        .frame(width: 24, height: 24)
        .background(personColor(p), in: Circle())
        .accessibilityIdentifier("set.performer.\((p?.isMe ?? true) ? "Me" : (p?.name ?? "?"))")
}
```

**2. The leading column becomes "Who" when partners are present.** In
`setColumnHeader`, swap the `Set` label for `Who` when `hasPartners`, and in
`completedSetRow` / `pendingRow` replace `setIndexBadge(...)` in the leading cell
with `performerChip(set.performedBy)` when `hasPartners` (fall back to the numeric
badge when solo). So each logged row shows who lifted it, and the alternation
reads down the column at a glance (M, A, M, A …). Keep the warm-up "W" treatment
by overlaying a small flame on the chip, or just rely on the existing per-row menu
toggle.

```swift
// leading cell in completedSetRow / pendingRow:
if hasPartners { performerChip(set.performedBy) } else { setIndexBadge(number, isWarmup: set.isWarmup) }
```

**3. The active row shows whose turn it is, and lets you switch in one tap.**
`openInlineEditor` already pre-selects `inlinePerformedByID = nextPerson()…`, so
the entry row defaults to the correct person. Surface that as a tappable turn
selector above the input line (replacing the partner `Picker` that was deleted
with the old editor). Add this as the first child of `activeSetRow`'s `VStack`,
shown only when `hasPartners`:

```swift
if hasPartners {
    Menu {
        Button { inlinePerformedByID = nil } label: {
            Label("Me", systemImage: inlinePerformedByID == nil ? "checkmark" : "")
        }
        ForEach(roster.filter { !$0.isMe }) { p in
            Button { inlinePerformedByID = p.id } label: {
                Label(p.name, systemImage: inlinePerformedByID == p.id ? "checkmark" : "")
            }
        }
    } label: {
        HStack(spacing: 5) {
            performerChip(people(for: inlinePerformedByID)).scaleEffect(0.72)
            Text("\(performerName(inlinePerformedByID))'s set")
                .font(.caption.weight(.medium)).foregroundStyle(.tint)
            Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.tint)
        }
    }
    .accessibilityIdentifier("inline.partner")
}
```

with a tiny helper: `performerName(_ id: UUID?) -> String` returns `"Me"` for nil,
else the person's first name. The active row's leading cell uses
`performerChip(people(for: inlinePerformedByID))` so it matches the selector.

`recordInlineSet` already reads `inlinePerformedByID` and writes
`editing.performedBy` / passes `performedBy:` into `addSet`, so completing the set
tags it to the right person and the rotation advances for the next one. Per-set
re-assignment of an already-logged set stays available in the row menu (§A4) — no
change needed there.

### A9 · End workout + cool-down (confirm, with a cool-down option)

The bottom of the live session already uses the shared `WorkoutControlBar` with a
teal **Cool Down** button above **Pause / End**, and End routes through a confirm.
Keep all of that. The only gap is that the End confirmation offers just "End /
Keep going" — so add the cool-down as a third choice inside that dialog, which is
the "End lets me cool down instead of immediately quitting" you want.

Edit `Cadence/Cadence/Features/Shared/WorkoutControlBar.swift` — add an optional
cool-down branch to the confirmation dialog:

```swift
.confirmationDialog(confirmTitle, isPresented: $confirming, titleVisibility: .visible) {
    if let onCoolDown {
        Button("Cool down, then finish") { onCoolDown() }
            .accessibilityIdentifier("workout.endCoolDown")
    }
    Button(endTitle, role: .destructive) { onEnd() }
        .accessibilityIdentifier("workout.endConfirm")
    Button("Keep going", role: .cancel) { }
        .accessibilityIdentifier("workout.endCancel")
} message: {
    if let confirmMessage { Text(confirmMessage) }
}
```

Because `SessionView` already passes `onCoolDown: { coolDownConfirm = true }` and
`confirmMessage: "This finishes and saves your workout."`, the End sheet now reads
**End workout?** → *Cool down, then finish* · *End* · *Keep going*, and the
cool-down path runs the existing `coolDownConfirm` → `GuidedPhaseOverlay`
(`cooldownMinutes`, teal) → `endWorkout()` flow untouched. The standalone Cool
Down button stays for a direct path; nothing else in `SessionView` changes.

This is a shared component, so the same three-way End dialog appears on the
cardio/interval screens — but only where a screen passes `onCoolDown`. Cardio and
interval pass `nil` (they bake in their own cool-down), so they keep the plain
End / Keep going dialog. No regression.

---

## Option B — minimal wrapping fix (if you want to ship today)

Keep `inlineEditor(for:)` but split its second `HStack` so the action buttons get
their own full-width row and can't be squeezed:

```swift
// Row 1 (weight/unit/reps) unchanged — but drop the fixed widths to be safe:
//   weight TextField: .frame(maxWidth: .infinity)   (instead of width: 80)

// Replace the single crowded HStack with two rows:

// Secondary line (read-only-ish context): alt weight, BW, partner, PR
HStack(spacing: 10) {
    if !altValue.isEmpty {
        Text("\u{2248} \(altValue)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
    }
    if isBodyweight(exercise) { Toggle("BW", isOn: $inlineBodyweight).toggleStyle(.button).controlSize(.mini) }
    if hasPartners { /* partner Picker */ }
    if wouldBePR { Label("PR", systemImage: "trophy.fill").font(.caption2.bold()).foregroundStyle(.orange) }
    Spacer()
}

// Action row: full-width, equal, never wraps
HStack(spacing: 12) {
    if inlineEditingSet != nil {
        Button(role: .destructive) { /* delete */ } label: {
            Image(systemName: "trash").frame(maxWidth: .infinity)
        }.buttonStyle(.bordered)
    }
    Button("Cancel") { closeInlineEditor() }
        .frame(maxWidth: .infinity).lineLimit(1).buttonStyle(.bordered)
    Button { recordInlineSet(for: exercise) } label: {
        Text(inlineEditingSet != nil ? "Save" : "Record").frame(maxWidth: .infinity).lineLimit(1)
    }
    .buttonStyle(.borderedProminent).disabled(!canSave)
}
.controlSize(.regular)
```

The `lineLimit(1)` + `.frame(maxWidth: .infinity)` on the action row is what stops
the one-word-per-line wrapping. This is a stopgap; Option A is the real fix.

---

## Definition of done (Option A)

- [ ] Each exercise shows a `Set · Prev · Weight · Reps · ✓` header and one row per
      set; columns stay aligned and nothing wraps on a small iPhone (test on SE).
- [ ] The set being entered is a highlighted row with weight/reps input cells and a
      single green checkmark that logs it and (live session) starts rest.
- [ ] Tapping a logged set's weight/reps re-opens it for editing; the gray previous
      value taps to prefill.
- [ ] Warm-up, bodyweight, performed-by, and delete are reachable via long-press on
      a row (and actually work — no more dead `swipeActions`).
- [ ] Warm-ups show a "W" badge; working sets number 1…n; PR rows show the trophy.
- [ ] "Add set" / "Repeat" are full-width and single-line; the per-set kg/lb
      segmented control is gone (unit shown once in the header).
- [ ] Partners (§A8): the `partnerBar` still adds people; with a partner present
      the leading column shows a colour-coded performer chip per row so alternation
      reads down the column; the active row shows "{Name}'s set ⌄", defaults to
      `nextPerson()`, and switches performer in one tap; partner sets earn no PR.
- [ ] End/cool-down (§A9): tapping End opens a confirmation (never quits
      immediately) offering *Cool down, then finish* · *End* · *Keep going*; the
      cool-down option runs the existing `GuidedPhaseOverlay` then ends; cardio/
      interval screens (which pass `onCoolDown: nil`) still show the 2-way dialog.
- [ ] All existing ids resolve: `inline.weight`, `inline.reps`, `inline.save`,
      `inline.cancel`, `inline.bodyweight`, `inline.partner`, `set.add.<name>`,
      `set.repeat.<name>`, `set.row.<name>.<n>`, `set.pending.<name>.<n>`,
      `set.prBadge`, `set.performer.<who>`, `partner.add`, `partner.chip.<who>`,
      `workout.coolDown`, `workout.endConfirm`, `workout.endCancel`, and the new
      `workout.endCoolDown`.
- [ ] App builds; `swift test` (engine untouched) stays green.
