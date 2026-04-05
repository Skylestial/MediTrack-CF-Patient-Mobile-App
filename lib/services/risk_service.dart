enum RiskLevel {
  low,      // Green - ≥80%
  moderate, // Amber - 50-79%
  high,     // Red - <50%
}

class RiskService {
  /// Strict Rule-Based Risk Calculation
  /// NO MACHINE LEARNING - Pure deterministic logic
  /// 
  /// Rules:
  /// - adherence >= 80 → Low Risk (Green)
  /// - adherence >= 50 && adherence < 80 → Moderate Risk (Amber)
  /// - adherence < 50 → High Risk (Red)
  static RiskLevel calculateRisk(int adherencePercentage) {
    if (adherencePercentage >= 80) {
      return RiskLevel.low;
    } else if (adherencePercentage >= 50) {
      return RiskLevel.moderate;
    } else {
      return RiskLevel.high;
    }
  }

  /// Calculate daily adherence percentage
  /// Returns 0-100
  static int calculateAdherence(int medicinesTaken, int totalMedicines) {
    if (totalMedicines == 0) return 0;
    return ((medicinesTaken / totalMedicines) * 100).round();
  }

  /// Get status string based on adherence
  static String getStatus(int adherencePercentage) {
    if (adherencePercentage == 100) {
      return 'fully';
    } else if (adherencePercentage > 0) {
      return 'partial';
    } else {
      return 'none';
    }
  }
}
