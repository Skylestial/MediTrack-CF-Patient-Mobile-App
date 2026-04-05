import 'package:flutter_test/flutter_test.dart';
import 'package:meditrack_patient/services/risk_service.dart';

void main() {
  group('RiskService - Strict Rule-Based Logic Tests', () {
    test('79% adherence returns Moderate Risk', () {
      final risk = RiskService.calculateRisk(79);
      expect(risk, RiskLevel.moderate);
    });

    test('80% adherence returns Low Risk', () {
      final risk = RiskService.calculateRisk(80);
      expect(risk, RiskLevel.low);
    });

    test('49% adherence returns High Risk', () {
      final risk = RiskService.calculateRisk(49);
      expect(risk, RiskLevel.high);
    });

    test('50% adherence returns Moderate Risk', () {
      final risk = RiskService.calculateRisk(50);
      expect(risk, RiskLevel.moderate);
    });

    test('100% adherence returns Low Risk', () {
      final risk = RiskService.calculateRisk(100);
      expect(risk, RiskLevel.low);
    });

    test('0% adherence returns High Risk', () {
      final risk = RiskService.calculateRisk(0);
      expect(risk, RiskLevel.high);
    });

    test('calculateAdherence returns correct percentage', () {
      expect(RiskService.calculateAdherence(8, 10), 80);
      expect(RiskService.calculateAdherence(5, 10), 50);
      expect(RiskService.calculateAdherence(4, 10), 40);
      expect(RiskService.calculateAdherence(10, 10), 100);
      expect(RiskService.calculateAdherence(0, 10), 0);
    });

    test('calculateAdherence handles zero total medicines', () {
      expect(RiskService.calculateAdherence(0, 0), 0);
    });

    test('getStatus returns correct status strings', () {
      expect(RiskService.getStatus(100), 'fully');
      expect(RiskService.getStatus(50), 'partial');
      expect(RiskService.getStatus(1), 'partial');
      expect(RiskService.getStatus(0), 'none');
    });

    test('Edge case: 81% adherence returns Low Risk', () {
      final risk = RiskService.calculateRisk(81);
      expect(risk, RiskLevel.low);
    });

    test('Edge case: 51% adherence returns Moderate Risk', () {
      final risk = RiskService.calculateRisk(51);
      expect(risk, RiskLevel.moderate);
    });
  });
}
