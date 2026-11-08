import '../../core/format.dart';
import '../auth/auth_models.dart';
import '../employee/employee_models.dart';

const roleLabels = {
  UserRole.employee: 'موظف',
  UserRole.manager: 'مدير مطعم',
  UserRole.admin: 'أدمن',
};

class AdminUser {
  const AdminUser({
    required this.id,
    required this.username,
    required this.fullName,
    this.department,
    required this.role,
    this.restaurantId,
    this.restaurantName,
    this.isActive = true,
    this.available = 0,
    this.held = 0,
  });

  final String id;
  final String username;
  final String fullName;
  final String? department;
  final UserRole role;
  final String? restaurantId;
  final String? restaurantName;
  final bool isActive;
  final int available;
  final int held;

  bool matches(String query) {
    final text = query.trim().toLowerCase();
    return text.isEmpty || fullName.toLowerCase().contains(text) || username.contains(text);
  }

  factory AdminUser.fromRow(Map<String, dynamic> row) {
    final restaurant = row['restaurants'] as Map<String, dynamic>?;
    final walletValue = row['wallets'];
    final wallet = walletValue is List ? (walletValue.isEmpty ? null : walletValue.first) : walletValue;
    return AdminUser(
      id: row['id'] as String,
      username: row['username'] as String,
      fullName: row['full_name'] as String,
      department: row['department'] as String?,
      role: UserRole.values.byName(row['role'] as String),
      restaurantId: row['restaurant_id'] as String?,
      restaurantName: restaurant?['name'] as String?,
      isActive: row['is_active'] as bool,
      available: ((wallet as Map<String, dynamic>?)?['available'] as num? ?? 0).toInt(),
      held: (wallet?['held'] as num? ?? 0).toInt(),
    );
  }
}

class Place {
  const Place({required this.id, required this.siteId, required this.name, required this.siteName, this.isActive = true});

  final String id;
  final String siteId;
  final String name;
  final String siteName;
  final bool isActive;

  factory Place.fromRow(Map<String, dynamic> row) => Place(
        id: row['id'] as String,
        siteId: row['site_id'] as String,
        name: row['name'] as String,
        siteName: (row['sites'] as Map<String, dynamic>)['name'] as String,
        isActive: row['is_active'] as bool,
      );
}

class RamadanPeriod {
  const RamadanPeriod({required this.hijriYear, required this.start, required this.end});

  final int hijriYear;
  final DateTime start;
  final DateTime end;

  factory RamadanPeriod.fromRow(Map<String, dynamic> row) => RamadanPeriod(
        hijriYear: row['hijri_year'] as int,
        start: DateTime.parse(row['start_date'] as String),
        end: DateTime.parse(row['end_date'] as String),
      );
}

class RamadanImpact {
  const RamadanImpact({required this.offerings, required this.bookings});

  final int offerings;
  final int bookings;
}

class LedgerLine {
  const LedgerLine({required this.isTopUp, required this.amount, this.employeeName, this.note, required this.createdAt});

  final bool isTopUp;
  final int amount;
  final String? employeeName;
  final String? note;
  final DateTime createdAt;

  String get text {
    final name = employeeName ?? 'موظف';
    return isTopUp ? 'شحن ${points(amount)} لـ$name' : 'تصحيح ${points(amount)} لـ$name: ${note ?? ''}';
  }

  factory LedgerLine.fromRow(Map<String, dynamic> row) {
    final wallet = row['wallets'] as Map<String, dynamic>?;
    final profile = wallet?['profiles'] as Map<String, dynamic>?;
    return LedgerLine(
      isTopUp: row['type'] == 'topup',
      amount: (row['available_delta'] as num).toInt(),
      employeeName: profile?['full_name'] as String?,
      note: row['note'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
    );
  }
}

class NewCredentials {
  const NewCredentials({required this.username, required this.password});

  final String username;
  final String password;
}

class AdminFailure implements Exception {
  const AdminFailure(this.message);

  final String message;

  static const network = AdminFailure('تعذّر الاتصال. تأكد من الإنترنت ثم حاول مرة أخرى.');
  static const unknown = AdminFailure('حدث خطأ. حاول مرة أخرى.');

  factory AdminFailure.fromCode(String code) => AdminFailure(switch (code) {
        'username_taken' => 'اسم المستخدم هذا مأخوذ. اختر اسماً آخر.',
        'invalid_username' => usernameRule,
        'invalid_full_name' => 'اكتب الاسم الكامل.',
        'restaurant_required' => 'اختر المطعم.',
        'restaurant_not_found' => 'هذا المطعم غير متاح.',
        'cannot_deactivate_self' => 'لا يمكنك تعطيل حسابك أنت.',
        'forbidden' => 'ليست لديك صلاحية لهذه العملية.',
        'unauthorized' => 'انتهت جلستك. سجّل الخروج ثم ادخل من جديد.',
        'invalid_amount' => 'اكتب عدد نقاط صحيحاً.',
        'empty_selection' => 'اختر موظفاً واحداً على الأقل.',
        'invalid_employee' => 'أحد الموظفين المختارين معطّل. لم يُشحن أحد.',
        'invalid_dates' => datesRule,
        'overlapping_period' => 'هذه التواريخ تتداخل مع رمضان آخر محفوظ.',
        _ => unknown.message,
      });
}

const usernameRule = 'اكتب اسم مستخدم بالإنجليزية من 3 أحرف على الأقل دون مسافات.';
const datesRule = 'اختر أول يوم وآخر يوم بالترتيب الصحيح.';

/// Same rules as the server, so most mistakes are caught before a request.
String? newUserProblem({required String fullName, required String username, required UserRole role, required String? restaurantId}) {
  if (fullName.trim().isEmpty) return 'اكتب الاسم الكامل.';
  if (!RegExp(r'^[a-z0-9._-]{3,32}$').hasMatch(normalizeUsername(username))) return usernameRule;
  if (role != UserRole.admin && restaurantId == null) return 'اختر المطعم.';
  return null;
}

/// The Hijri year holding a date, from the civil calendar. A moon sighting moves Ramadan
/// by a day or two at most, and month 9 is far from the year's edges, so a corrected date
/// still lands in the same year.
int hijriYearOf(DateTime date) {
  final julianDay = DateTime.utc(date.year, date.month, date.day).difference(DateTime.utc(1970)).inDays + 2440588;
  return (30 * (julianDay - 1948440) + 10646) ~/ 10631;
}

/// The Saturday that starts the week holding this day.
DateTime weekStartOf(DateTime day) => addDays(dayOf(day), -((day.weekday % 7 + 1) % 7));

class WeekRow {
  const WeekRow({required this.date, required this.period, required this.status, required this.restaurantId, this.count = 1});

  final DateTime date;
  final MealPeriod period;
  final BookingStatus status;
  final String restaurantId;

  /// How many bookings this row stands for; the server sends them already counted.
  final int count;

  factory WeekRow.fromRow(Map<String, dynamic> row) => WeekRow(
        date: DateTime.parse(row['service_date'] as String),
        period: MealPeriod.values.byName(row['period'] as String),
        status: parseBookingStatus(row['status'] as String),
        restaurantId: row['restaurant_id'] as String,
        count: (row['bookings'] as num).toInt(),
      );
}

class WeekDayCount {
  const WeekDayCount({required this.day, required this.lines});

  final DateTime day;

  /// Meals per calendar line: morning, midday, evening.
  final List<int> lines;

  int get total => lines.fold(0, (sum, count) => sum + count);
}

class WeekSummary {
  const WeekSummary({required this.days, required this.collected, required this.notCollected, required this.waiting, required this.cancelled, required this.byRestaurant});

  final List<WeekDayCount> days;
  final int collected;
  final int notCollected;
  final int waiting;
  final int cancelled;
  final Map<String, int> byRestaurant;

  /// Cancelled bookings count only as an outcome: no meal was served for them.
  factory WeekSummary.from(DateTime start, List<WeekRow> rows) {
    bool served(WeekRow row) => row.status != BookingStatus.cancelled && row.status != BookingStatus.cancelledByRestaurant;
    final days = [
      for (var offset = 0; offset < 7; offset++)
        () {
          final day = addDays(start, offset);
          final lines = [0, 0, 0];
          for (final row in rows) {
            if (row.date == day && served(row)) lines[row.period.calendarLine] += row.count;
          }
          return WeekDayCount(day: day, lines: lines);
        }(),
    ];
    final byRestaurant = <String, int>{};
    for (final row in rows.where(served)) {
      byRestaurant[row.restaurantId] = (byRestaurant[row.restaurantId] ?? 0) + row.count;
    }
    int count(bool Function(WeekRow) test) => rows.where(test).fold(0, (sum, row) => sum + row.count);
    return WeekSummary(
      days: days,
      collected: count((row) => row.status == BookingStatus.pickedUp),
      notCollected: count((row) => row.status == BookingStatus.noShow),
      waiting: count((row) => row.status == BookingStatus.booked),
      cancelled: count((row) => !served(row)),
      byRestaurant: byRestaurant,
    );
  }
}
