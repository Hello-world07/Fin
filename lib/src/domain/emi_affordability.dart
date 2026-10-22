int? personalEmiIncomePercent(int scheduledPaise, int? incomePaise) {
  if (incomePaise == null || incomePaise <= 0) return null;
  return (scheduledPaise * 100 / incomePaise).round();
}

String personalEmiIncomeZone(int? percent) => switch (percent) {
  null => 'Add income',
  < 30 => 'Comfortable',
  < 40 => 'Watchful',
  < 50 => 'High',
  _ => 'Very high',
};
