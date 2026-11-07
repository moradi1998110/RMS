import 'package:rms/features/employee/employee_models.dart';
import 'package:rms/features/employee/employee_repository.dart';

class FakeEmployeeRepository implements EmployeeRepository {
  FakeEmployeeRepository({
    this.walletValue = const Wallet(available: 50000, held: 6000),
    this.offeringsValue = const [],
    this.bookingsValue = const [],
    this.transactionsValue = const [],
  });

  Wallet walletValue;
  List<Offering> offeringsValue;
  List<Booking> bookingsValue;
  List<WalletTx> transactionsValue;

  /// Thrown once by the next action, then cleared.
  EmployeeFailure? failNext;

  final bookCalls = <(List<String>, String)>[];
  final cancelCalls = <(String, String)>[];
  final seriesCalls = <(String, String)>[];

  void _maybeFail() {
    final failure = failNext;
    failNext = null;
    if (failure != null) throw failure;
  }

  @override
  Future<Wallet> wallet() async => walletValue;

  @override
  Future<List<Offering>> offerings(DateTime from, DateTime until) async {
    offeringsCalls.add((from, until));
    return offeringsValue.where((offering) => !offering.serviceDate.isBefore(from) && !offering.serviceDate.isAfter(until)).toList();
  }

  final offeringsCalls = <(DateTime, DateTime)>[];

  @override
  Future<List<Booking>> activeBookings(DateTime from) async => bookingsValue;

  @override
  Future<List<Booking>> monthBookings(DateTime month) async => bookingsValue
      .where((booking) => booking.serviceDate.year == month.year && booking.serviceDate.month == month.month)
      .toList();

  @override
  Future<List<WalletTx>> transactions({int limit = transactionsPage}) async => transactionsValue.take(limit).toList();

  @override
  Future<BookResult> book(List<String> offeringIds, String key) async {
    bookCalls.add((offeringIds, key));
    _maybeFail();
    return BookResult(count: offeringIds.length, total: 0);
  }

  @override
  Future<CancelResult> cancel(String bookingId, String key) async {
    cancelCalls.add((bookingId, key));
    _maybeFail();
    bookingsValue = bookingsValue.where((booking) => booking.id != bookingId).toList();
    return const CancelResult(count: 1, refunded: 6000);
  }

  @override
  Future<CancelResult> cancelSeries(String bookingId, String key) async {
    seriesCalls.add((bookingId, key));
    _maybeFail();
    return const CancelResult(count: 3, refunded: 18000);
  }

  List<Pickup> pickupsValue = const [];

  @override
  Future<List<Pickup>> pickups() async => pickupsValue;

  List<Delegate> delegatesValue = const [];
  Map<String, Colleague> colleagues = const {};
  final addDelegateCalls = <(String, String)>[];
  final removeDelegateCalls = <String>[];

  @override
  Future<List<Delegate>> delegates() async {
    // Fails this many times first, like a weak connection or a server not yet updated.
    if (delegatesFailures > 0) {
      delegatesFailures--;
      throw EmployeeFailure.network;
    }
    return delegatesValue;
  }

  int delegatesFailures = 0;

  @override
  Future<Colleague?> findColleague(String username) async {
    _maybeFail();
    return colleagues[username.trim().toLowerCase()];
  }

  @override
  Future<void> addDelegate(String username, String key) async {
    addDelegateCalls.add((username, key));
    _maybeFail();
    final colleague = colleagues[username]!;
    delegatesValue = [
      ...delegatesValue,
      Delegate(delegationId: 'd-${colleague.username}', username: colleague.username, fullName: colleague.fullName, department: colleague.department),
    ];
  }

  @override
  Future<void> removeDelegate(String delegationId) async {
    removeDelegateCalls.add(delegationId);
    _maybeFail();
    delegatesValue = delegatesValue.where((delegate) => delegate.delegationId != delegationId).toList();
  }

  List<RatableMeal> ratableValue = const [];
  final rateCalls = <({String bookingId, int stars, Set<RatingTag> tags, String comment, String key})>[];

  @override
  Future<List<RatableMeal>> ratableMeals() async => ratableValue;

  @override
  Future<void> rateMeal({required String bookingId, required int stars, required Set<RatingTag> tags, required String comment, required String key}) async {
    rateCalls.add((bookingId: bookingId, stars: stars, tags: tags, comment: comment, key: key));
    _maybeFail();
    ratableValue = ratableValue.where((meal) => meal.bookingId != bookingId).toList();
  }

  @override
  String imageUrl(String path) => 'https://example.invalid/$path';
}
