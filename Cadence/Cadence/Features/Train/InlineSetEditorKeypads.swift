import SwiftUI
import CadenceCore
import CadenceFeatures
import CadenceWorkoutFeatures
import CadencePhoneFeatures

/// The two numeric keypad sheets live in their own file to keep the main set
/// editor under the test-pyramid LOC cap. They are presentation-only and share
/// the editor's already-validated draft state.
extension InlineSetEditorView {
    var keypad: some View {
        NavigationStack { VStack(spacing: 12) { TextField("Weight", text: $typedWeight).keyboardType(.decimalPad).font(.largeTitle.monospacedDigit()).multilineTextAlignment(.center).textFieldStyle(.roundedBorder).padding(); if let keypadError { Text(keypadError).font(.caption).foregroundStyle(CadenceTheme.attention) }; ForEach([["1","2","3"],["4","5","6"],["7","8","9"],[".","0","⌫"]], id: \.self) { row in HStack { ForEach(row, id: \.self) { key in Button(key) { if key == "⌫" { if !typedWeight.isEmpty { typedWeight.removeLast() } } else if key == "." && !typedWeight.contains(".") { typedWeight += "." } else if key != "." { typedWeight += key } }.font(.title).frame(maxWidth: .infinity, minHeight: 56).buttonStyle(.bordered) } } }; Spacer() }.padding().navigationTitle(config.bodyweight ? "Enter added weight" : "Enter weight").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { if let value = Double(typedWeight), value.isFinite { hasExplicitWeightEntry = true; draft.setWeight(value); keypadError = nil; keypadPresented = false } else { keypadError = "Enter a valid number" } } } } }
    }
    var repsKeypad: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text(typedReps.isEmpty ? "0" : typedReps)
                    .font(.largeTitle.monospacedDigit().bold())
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .accessibilityIdentifier("setEditor.reps.typed")
                ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "⌫"]], id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { key in
                            Button(key.isEmpty ? " " : key) {
                                if key == "⌫" {
                                    if !typedReps.isEmpty { typedReps.removeLast() }
                                } else if !key.isEmpty, typedReps.count < 3 {
                                    if typedReps == "0" { typedReps = key } else { typedReps += key }
                                }
                            }
                            .font(.title)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .buttonStyle(.bordered)
                            .disabled(key.isEmpty)
                        }
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Enter reps")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let reps = Int(typedReps), (1...100).contains(reps) {
                            draft.setReps(reps)
                            repsKeypadPresented = false
                        }
                    }
                }
            }
        }
    }
}
