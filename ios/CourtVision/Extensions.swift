import SwiftUI

// MARK: - Color Extensions
extension Color {
    // MARK: - Brand Colors
    static let basketballOrange = Color(hex: "#FF6B35")
    static let deepNavy = Color(hex: "#1B365D")
    static let charcoal = Color(hex: "#2C2C2E")
    
    // MARK: - Semantic Colors
    static let shotMake = Color(hex: "#30D158") // iOS system green
    static let shotMiss = Color(hex: "#FF3B30") // iOS system red
    static let shotPending = Color(hex: "#FF9500") // iOS system orange
    static let shotInfo = Color(hex: "#007AFF") // iOS system blue
    
    // MARK: - Background Colors
    static let courtBackground = Color(hex: "#F2F2F7") // iOS system gray 6
    static let cardBackground = Color.white
    
    // MARK: - Helper initializer for hex colors
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Extensions
extension View {
    // MARK: - Card Styling
    func basketballCard() -> some View {
        self
            .background(Color.cardBackground)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Button Styling
    func primaryButton() -> some View {
        self
            .foregroundColor(.white)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .background(Color.basketballOrange)
            .cornerRadius(12)
            .shadow(color: Color.basketballOrange.opacity(0.3), radius: 12, x: 0, y: 4)
    }
    
    func secondaryButton() -> some View {
        self
            .foregroundColor(.basketballOrange)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 22)
            .background(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.basketballOrange, lineWidth: 2)
            )
            .cornerRadius(12)
    }
    
    func destructiveButton() -> some View {
        self
            .foregroundColor(.white)
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .background(Color.shotMiss)
            .cornerRadius(12)
    }
    
    // MARK: - Status Chip Styling
    func statusChip(type: ChipType) -> some View {
        self
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(type.backgroundColor)
            .foregroundColor(type.foregroundColor)
            .cornerRadius(6)
    }
    
    // MARK: - Shadow Styling
    func basketballShadow() -> some View {
        self.shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 2)
    }
    
    // MARK: - Spacing
    func basketballPadding() -> some View {
        self.padding(16)
    }
    
    func basketballSpacing() -> some View {
        self.padding(.vertical, 24)
    }
}

// MARK: - ChipType Enum
enum ChipType {
    case make
    case miss
    case pending
    case shotType
    
    var backgroundColor: Color {
        switch self {
        case .make:
            return Color.shotMake.opacity(0.1)
        case .miss:
            return Color.shotMiss.opacity(0.1)
        case .pending:
            return Color.shotPending.opacity(0.1)
        case .shotType:
            return Color.shotInfo.opacity(0.1)
        }
    }
    
    var foregroundColor: Color {
        switch self {
        case .make:
            return Color.shotMake
        case .miss:
            return Color.shotMiss
        case .pending:
            return Color.shotPending
        case .shotType:
            return Color.shotInfo
        }
    }
}
