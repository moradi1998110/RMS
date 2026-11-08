/// Arabic wording for money, dates and times. Every time reaches the user as a
/// sentence, not as a bare timestamp.
const _weekdays = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
const _months = [
  'كانون الثاني',
  'شباط',
  'آذار',
  'نيسان',
  'أيار',
  'حزيران',
  'تموز',
  'آب',
  'أيلول',
  'تشرين الأول',
  'تشرين الثاني',
  'كانون الأول',
];

/// Column headings of the month calendar, which starts on Saturday.
const calendarHeads = ['سبت', 'أحد', 'اثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة'];

String money(int amount) {
  final digits = amount.abs().toString();
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return amount < 0 ? '-$grouped' : grouped.toString();
}

/// Balances, prices and top-ups are points, one point for each unit stored.
/// The word agrees with the number as Arabic needs: 2 نقطتان, 3–10 نقاط, else نقطة.
String pointsWord(int amount) => switch (amount.abs()) {
      2 => 'نقطتان',
      >= 3 && <= 10 => 'نقاط',
      _ => 'نقطة',
    };

/// "6,000 نقطة", "5 نقاط", "نقطة واحدة".
String points(int amount) => switch (amount.abs()) {
      1 => amount < 0 ? '-نقطة واحدة' : 'نقطة واحدة',
      2 => amount < 0 ? '-نقطتان' : 'نقطتان',
      _ => '${money(amount)} ${pointsWord(amount)}',
    };

DateTime dayOf(DateTime time) => DateTime(time.year, time.month, time.day);

bool sameMonth(DateTime a, DateTime b) => a.year == b.year && a.month == b.month;

/// Calendar arithmetic, safe across daylight saving changes.
DateTime addDays(DateTime day, int days) => DateTime(day.year, day.month, day.day + days);

String isoDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

String weekdayName(DateTime day) => _weekdays[day.weekday % 7];

String monthName(DateTime day) => _months[day.month - 1];

String shortDate(DateTime day) => '${day.day} ${monthName(day)}';

String longDate(DateTime day) => '${weekdayName(day)} ${shortDate(day)}';

String relativeDay(DateTime day, DateTime today) {
  if (day == today) return 'اليوم';
  if (day == addDays(today, 1)) return 'غداً';
  return longDate(day);
}

String _partOfDay(DateTime time) {
  if (time.hour < 12) return 'صباحاً';
  if (time.hour < 16) return 'ظهراً';
  return 'مساءً';
}

String _clockDigits(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  return '$hour:${time.minute.toString().padLeft(2, '0')}';
}

String clock(DateTime time) => '${_clockDigits(time)} ${_partOfDay(time)}';

String clockRange(DateTime from, DateTime until) {
  if (_partOfDay(from) == _partOfDay(until)) {
    return 'من ${_clockDigits(from)} إلى ${clock(until)}';
  }
  return 'من ${clock(from)} إلى ${clock(until)}';
}

/// A deadline told relative to the day of the meal it belongs to.
String deadlineText(DateTime deadline, DateTime serviceDate) {
  final day = dayOf(deadline);
  if (day == serviceDate) return '${clock(deadline)} يوم الوجبة';
  if (day == addDays(serviceDate, -1)) {
    return '${deadline.hour >= 18 ? 'الليلة السابقة' : 'اليوم السابق'} ${clock(deadline)}';
  }
  return '${longDate(day)} ${clock(deadline)}';
}

/// "وجبتان" as the subject of a sentence.
String mealCount(int count) => switch (count) {
      1 => 'وجبة واحدة',
      2 => 'وجبتان',
      _ => '$count وجبات',
    };

/// "وجبتين" as the object of a sentence.
String mealCountObject(int count) => switch (count) {
      1 => 'وجبة واحدة',
      2 => 'وجبتين',
      _ => '$count وجبات',
    };

/// The name of a day numbered as the server does: 0 = Sunday ... 6 = Saturday.
String weekdayNameOf(int dayOfWeek) => _weekdays[dayOfWeek];

/// Days of the week in calendar order, starting on Saturday.
const weekOrder = [6, 0, 1, 2, 3, 4, 5];
