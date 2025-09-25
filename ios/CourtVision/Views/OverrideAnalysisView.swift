import SwiftUI

struct OverrideAnalysisView: View {
    @Binding var isPresented: Bool
    let clipData: ClipWithAnalysis
    let onSave: (String, String, String?) -> Void // fieldName, overrideValue, originalValue
    
    @State private var selectedShotType: ShotType?
    @State private var selectedResult: ShotResult?
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    private var hasChanges: Bool {
        selectedShotType != nil || selectedResult != nil
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.basketballOrange)
                        
                        Text("Correct Analysis")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.charcoal)
                        
                        Text("Help improve CourtVision by correcting any mistakes in the AI analysis")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .basketballPadding()
                    
                    // Shot Type Correction Section
                    VStack(spacing: 16) {
                        OverrideFieldSection(
                            title: "Shot Type",
                            aiValue: clipData.displayShotType,
                            aiRawValue: clipData.shot_type,
                            hasOverride: clipData.overrides?.contains(where: { $0.field_name == "shot_type" }) ?? false,
                            content: {
                                ShotTypePickerView(selection: $selectedShotType)
                            }
                        )
                        
                        // Result Correction Section
                        OverrideFieldSection(
                            title: "Make/Miss",
                            aiValue: clipData.displayResult,
                            aiRawValue: clipData.result,
                            hasOverride: clipData.overrides?.contains(where: { $0.field_name == "result" }) ?? false,
                            content: {
                                ResultPickerView(selection: $selectedResult)
                            }
                        )
                    }
                    
                    // Error Message
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.shotMiss)
                            .font(.caption)
                            .basketballCard()
                            .basketballPadding()
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .background(Color.courtBackground)
            .navigationTitle("Correct Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.secondary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveOverrides()
                    }
                    .disabled(isSaving || !hasChanges)
                    .fontWeight(.semibold)
                    .foregroundColor(hasChanges ? .basketballOrange : .secondary)
                }
            }
        }
        .onAppear {
            // Pre-populate with current values if there are existing overrides
            if let shotTypeOverride = clipData.overrides?.first(where: { $0.field_name == "shot_type" }) {
                selectedShotType = ShotType(rawValue: shotTypeOverride.override_value)
            }
            if let resultOverride = clipData.overrides?.first(where: { $0.field_name == "result" }) {
                selectedResult = ShotResult(rawValue: resultOverride.override_value)
            }
        }
    }
    
    private func saveOverrides() {
        isSaving = true
        errorMessage = nil
        
        print("🔧 OverrideAnalysisView: Starting save process")
        print("🔧 Selected shot type: \(selectedShotType?.rawValue ?? "none")")
        print("🔧 Selected result: \(selectedResult?.rawValue ?? "none")")
        print("🔧 Clip analysis ID: \(clipData.analysis_id ?? "none")")
        
        // Save shot type override if changed
        if let shotType = selectedShotType {
            print("🔧 Saving shot type override: \(shotType.rawValue)")
            onSave("shot_type", shotType.rawValue, clipData.shot_type)
        }
        
        // Save result override if changed
        if let result = selectedResult {
            print("🔧 Saving result override: \(result.rawValue)")
            onSave("result", result.rawValue, clipData.result)
        }
        
        isPresented = false
        isSaving = false
    }
}

struct OverrideFieldSection<Content: View>: View {
    let title: String
    let aiValue: String
    let aiRawValue: String?
    let hasOverride: Bool
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section Header
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.charcoal)
                
                if hasOverride {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.basketballOrange)
                        .font(.caption)
                }
                
                Spacer()
            }
            
            // Current AI Value
            VStack(alignment: .leading, spacing: 8) {
                Text("AI Detected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                
                Text(aiValue)
                    .statusChip(type: getChipType(for: aiRawValue))
            }
            
            // Correction Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Correction")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fontWeight(.medium)
                
                content
            }
        }
        .basketballCard()
        .basketballPadding()
    }
    
    private func getChipType(for value: String?) -> ChipType {
        guard let value = value else { return .pending }
        
        switch value {
        case "make": return .make
        case "miss": return .miss
        default: return .shotType
        }
    }
}

struct ShotTypePickerView: View {
    @Binding var selection: ShotType?
    
    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            ForEach(ShotType.allCases, id: \.self) { shotType in
                Button(action: {
                    selection = shotType
                }) {
                    Text(shotType.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(selection == shotType ? .white : .charcoal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selection == shotType ? Color.basketballOrange : Color.white)
                                .stroke(selection == shotType ? Color.basketballOrange : Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

struct ResultPickerView: View {
    @Binding var selection: ShotResult?
    
    var body: some View {
        HStack(spacing: 16) {
            ForEach(ShotResult.allCases, id: \.self) { result in
                Button(action: {
                    selection = result
                }) {
                    HStack {
                        Image(systemName: result == .make ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(selection == result ? .white : (result == .make ? .shotMake : .shotMiss))
                        
                        Text(result.displayName)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(selection == result ? .white : .charcoal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selection == result ? (result == .make ? Color.shotMake : Color.shotMiss) : Color.white)
                            .stroke(selection == result ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

#Preview {
    OverrideAnalysisView(
        isPresented: .constant(true),
        clipData: ClipWithAnalysis(
            id: "test",
            storage_key: "test",
            duration_s: 10,
            created_at: Date(),
            analysis_id: "test",
            analysis_status: "success",
            shot_type: "mid_range",
            result: "miss",
            confidence: 0.85,
            tips_text: "Test tips",
            error_msg: nil,
            analysis_created_at: Date(),
            started_at: Date(),
            completed_at: Date(),
            overrides: nil
        ),
        onSave: { _, _, _ in }
    )
}
