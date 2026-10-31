import 'package:flutter_test/flutter_test.dart';
import '../../tool/nara_medical_recovery_probe.dart';

void main() {
  test(
    '10000 supported activities and 200 empty medical entries recover safely',
    () async {
      final result = await runMedicalRecoveryProbe();
      expect(result['passed'], true);
      expect(result['supported_activities'], 10000);
      expect(result['medical_exclusions'], 200);
      expect(result['corrected_components'], 400);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
