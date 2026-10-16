/// US liquid fluid ounces (not Imperial fluid ounces or ounces by weight).
const mlPerUsFlOz = 29.5735295625;

enum VolumeUnit {
  ml('ml'),
  oz('oz');

  const VolumeUnit(this.label);
  final String label;
  double toMl(double value) => this == ml ? value : value * mlPerUsFlOz;
  double fromMl(double value) => this == ml ? value : value / mlPerUsFlOz;
}

String volumeNumber(double value) {
  if (value > 0 && value < 0.01) return '<0.01';
  return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

String volumeLabel(double ml, {required VolumeUnit unit}) =>
    '${volumeNumber(unit.fromMl(ml))} ${unit.label}';
