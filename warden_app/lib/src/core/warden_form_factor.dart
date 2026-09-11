import 'package:flutter/foundation.dart';

enum WardenFormFactor { desktop, mobile }

const _configuredFormFactor = String.fromEnvironment(
  'WARDEN_FORM_FACTOR',
  defaultValue: 'auto',
);

WardenFormFactor get kWardenFormFactor {
  switch (_configuredFormFactor) {
    case 'desktop':
      return WardenFormFactor.desktop;
    case 'mobile':
      return WardenFormFactor.mobile;
    default:
      return defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS
          ? WardenFormFactor.mobile
          : WardenFormFactor.desktop;
  }
}

bool get kWardenMobile => kWardenFormFactor == WardenFormFactor.mobile;

void assertValidWardenFormFactor() {
  assert(
    _configuredFormFactor == 'auto' ||
        _configuredFormFactor == 'desktop' ||
        _configuredFormFactor == 'mobile',
    'WARDEN_FORM_FACTOR must be auto, desktop, or mobile.',
  );
}

abstract final class WardenLayout {
  static double get pagePadding => kWardenMobile ? 20.0 : 32.0;
  static double get sectionGap => kWardenMobile ? 24.0 : 32.0;
  static const maxContentWidth = 1040.0;
  static const cardRadius = 18.0;
}
