class SystemSettingsModel {
  const SystemSettingsModel({
    this.offlineTimeoutSeconds = 300,
    this.movementThresholdMps = 0.5,
    this.defaultGapThresholdSeconds = 300,
  });

  final int offlineTimeoutSeconds;
  final double movementThresholdMps;
  final int defaultGapThresholdSeconds;

  factory SystemSettingsModel.fromJson(Map<String, dynamic> json) {
    return SystemSettingsModel(
      offlineTimeoutSeconds: _intValue(json['offline_timeout_seconds']) ?? 300,
      movementThresholdMps: _doubleValue(json['movement_threshold_mps']) ?? 0.5,
      defaultGapThresholdSeconds:
          _intValue(json['default_gap_threshold_seconds']) ?? 300,
    );
  }

  Map<String, dynamic> toJson() => {
    'offline_timeout_seconds': offlineTimeoutSeconds,
    'movement_threshold_mps': movementThresholdMps,
    'default_gap_threshold_seconds': defaultGapThresholdSeconds,
  };

  SystemSettingsModel copyWith({
    int? offlineTimeoutSeconds,
    double? movementThresholdMps,
    int? defaultGapThresholdSeconds,
  }) {
    return SystemSettingsModel(
      offlineTimeoutSeconds:
          offlineTimeoutSeconds ?? this.offlineTimeoutSeconds,
      movementThresholdMps: movementThresholdMps ?? this.movementThresholdMps,
      defaultGapThresholdSeconds:
          defaultGapThresholdSeconds ?? this.defaultGapThresholdSeconds,
    );
  }

  static int? _intValue(dynamic value) => switch (value) {
    int number => number,
    num number => number.toInt(),
    String text => int.tryParse(text),
    _ => null,
  };

  static double? _doubleValue(dynamic value) => switch (value) {
    num number => number.toDouble(),
    String text => double.tryParse(text),
    _ => null,
  };
}
