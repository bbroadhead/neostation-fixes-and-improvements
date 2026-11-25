import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/game/ra_launch_readiness.dart';

void main() {
  test(
    'requires affirmative configuration evidence for verified readiness',
    () {
      expect(
        RaLaunchReadinessService.fromSettings(
          achievements: true,
          hardcore: true,
        ),
        RaLaunchReadiness.verified,
      );
      expect(
        RaLaunchReadinessService.fromSettings(
          achievements: true,
          hardcore: false,
        ),
        RaLaunchReadiness.warning,
      );
      expect(
        RaLaunchReadinessService.fromSettings(
          achievements: false,
          hardcore: null,
        ),
        RaLaunchReadiness.warning,
      );
      expect(
        RaLaunchReadinessService.fromSettings(
          achievements: true,
          hardcore: null,
        ),
        RaLaunchReadiness.unknown,
      );
    },
  );
}
