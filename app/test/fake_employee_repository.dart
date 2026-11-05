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
  Future<List<Offering>> offerings(DateTime from) async => offeringsValue;

  @override
  Future<List<Booking>> activeBookings(DateTime from) async => bookingsValue;

  @override
  Future<List<Booking>> monthBookings(DateTime month) async => bookingsValue
      .where((booking) => booking.serviceDate.year == month.year && booking.serviceDate.month == month.month)
      .toList();

  @override
  Future<List<WalletTx>> transactions() async => transactionsValue;

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
    return const CancelResult(count: 1, refunded: 6000);
  }

  @override
  Future<CancelResult> cancelSeries(String bookingId, String key) async {
    seriesCalls.add((bookingId, key));
    _maybeFail();
    return const CancelResult(count: 3, refunded: 18000);
  }

  @override
  String imageUrl(String path) => 'https://example.invalid/$path';
}
