import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/format.dart';
import 'employee_models.dart';

abstract class EmployeeRepository {
  Future<Wallet> wallet();
  /// Open meals served from [from] to [until], both days included.
  Future<List<Offering>> offerings(DateTime from, DateTime until);

  /// Bookings not cancelled, from this day on.
  Future<List<Booking>> activeBookings(DateTime from);
  Future<List<Booking>> monthBookings(DateTime month);
  /// The latest [limit] movements, newest first.
  Future<List<WalletTx>> transactions({int limit = transactionsPage});
  Future<BookResult> book(List<String> offeringIds, String key);
  Future<CancelResult> cancel(String bookingId, String key);
  Future<CancelResult> cancelSeries(String bookingId, String key);
  Future<List<Pickup>> pickups();
  Future<List<Delegate>> delegates();

  /// Null when no colleague at my restaurant has this username.
  Future<Colleague?> findColleague(String username);
  Future<void> addDelegate(String username, String key);
  Future<void> removeDelegate(String delegationId);
  Future<List<RatableMeal>> ratableMeals();
  Future<void> rateMeal({required String bookingId, required int stars, required Set<RatingTag> tags, required String comment, required String key});
  String imageUrl(String path);
}

final employeeRepositoryProvider = Provider<EmployeeRepository>(
  (ref) => SupabaseEmployeeRepository(Supabase.instance.client),
);

const _bookingColumns = 'id, offering_id, amount, status, '
    'meal_offerings!inner(meal_id, service_date, period, cancel_until, pickup_from, pickup_until, meals(name))';

class SupabaseEmployeeRepository implements EmployeeRepository {
  SupabaseEmployeeRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Wallet> wallet() => _guard(() async {
        final row = await _client.from('wallets').select('available, held').maybeSingle();
        return row == null ? const Wallet(available: 0, held: 0) : Wallet.fromRow(row);
      });

  @override
  Future<List<Offering>> offerings(DateTime from, DateTime until) => _guard(() async {
        final rows = await _client
            .from('meal_offerings')
            .select('id, meal_id, service_date, period, price, book_until, cancel_until, pickup_from, pickup_until, '
                'capacity, booked_count, meals(name, description, image_path, has_salad, has_soft_drink, has_juice, has_vegetables)')
            .eq('status', 'open')
            .gte('service_date', isoDate(from))
            .lte('service_date', isoDate(until))
            .order('service_date', ascending: true);
        return rows.map(Offering.fromRow).toList();
      });

  @override
  Future<List<Booking>> activeBookings(DateTime from) => _guard(() async {
        final rows = await _client
            .from('bookings')
            .select(_bookingColumns)
            .inFilter('status', ['booked', 'picked_up', 'no_show'])
            .gte('meal_offerings.service_date', isoDate(from));
        return rows.map(Booking.fromRow).toList();
      });

  @override
  Future<List<Booking>> monthBookings(DateTime month) => _guard(() async {
        final rows = await _client
            .from('bookings')
            .select(_bookingColumns)
            .inFilter('status', ['booked', 'picked_up', 'no_show', 'cancelled_by_restaurant'])
            .gte('meal_offerings.service_date', isoDate(DateTime(month.year, month.month)))
            .lt('meal_offerings.service_date', isoDate(DateTime(month.year, month.month + 1)));
        return rows.map(Booking.fromRow).toList();
      });

  @override
  Future<List<WalletTx>> transactions({int limit = transactionsPage}) => _guard(() async {
        final rows = await _client
            .from('wallet_transactions')
            .select('type, available_delta, held_delta, note, created_at, bookings(meal_offerings(meals(name)))')
            .order('id', ascending: false)
            .limit(limit);
        return rows.map(WalletTx.fromRow).toList();
      });

  @override
  Future<BookResult> book(List<String> offeringIds, String key) => _guard(() async {
        final result = await _client.rpc('book_meals', params: {'p_offering_ids': offeringIds, 'p_key': key}) as Map<String, dynamic>;
        return BookResult(count: (result['booking_ids'] as List).length, total: (result['total'] as num).toInt());
      });

  @override
  Future<CancelResult> cancel(String bookingId, String key) => _guard(() async {
        final result = await _client.rpc('cancel_booking', params: {'p_booking_id': bookingId, 'p_key': key}) as Map<String, dynamic>;
        return CancelResult(count: 1, refunded: (result['refunded'] as num).toInt());
      });

  @override
  Future<CancelResult> cancelSeries(String bookingId, String key) => _guard(() async {
        final result = await _client.rpc('cancel_booking_series', params: {'p_booking_id': bookingId, 'p_key': key}) as Map<String, dynamic>;
        return CancelResult(count: (result['cancelled'] as num).toInt(), refunded: (result['refunded'] as num).toInt());
      });

  @override
  Future<List<Pickup>> pickups() => _guard(() async {
        final rows = await _client.rpc('my_pickups') as List;
        return [for (final row in rows) Pickup.fromRow(row as Map<String, dynamic>)];
      });

  @override
  Future<List<Delegate>> delegates() => _guard(() async {
        final rows = await _client.rpc('my_delegates') as List;
        return [for (final row in rows) Delegate.fromRow(row as Map<String, dynamic>)];
      });

  @override
  Future<Colleague?> findColleague(String username) => _guard(() async {
        final row = await _client.rpc('find_colleague', params: {'p_username': username.trim()});
        return row == null ? null : Colleague.fromRow(row as Map<String, dynamic>);
      });

  @override
  Future<void> addDelegate(String username, String key) => _guard(() async {
        await _client.rpc('set_delegation', params: {'p_delegate_username': username.trim(), 'p_booking_id': null, 'p_key': key});
      });

  @override
  Future<void> removeDelegate(String delegationId) => _guard(() async {
        await _client.rpc('revoke_delegation', params: {'p_delegation_id': delegationId});
      });

  @override
  Future<List<RatableMeal>> ratableMeals() => _guard(() async {
        final rows = await _client.rpc('my_ratable_meals') as List;
        return [for (final row in rows) RatableMeal.fromRow(row as Map<String, dynamic>)];
      });

  @override
  Future<void> rateMeal({required String bookingId, required int stars, required Set<RatingTag> tags, required String comment, required String key}) =>
      _guard(() async {
        await _client.rpc('rate_meal', params: {
          'p_booking_id': bookingId,
          'p_stars': stars,
          'p_tags': [for (final tag in tags) tag.code],
          'p_comment': comment.trim(),
          'p_key': key,
        });
      });

  @override
  String imageUrl(String path) => _client.storage.from('meal-images').getPublicUrl(path);

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (error) {
      // Rejections from our functions carry errcode P0001, a code and JSON details.
      if (error.code != 'P0001') throw EmployeeFailure.unknown;
      throw EmployeeFailure.fromServer(error.message, _details(error.details));
    } on AuthException {
      throw EmployeeFailure.network;
    } on Exception {
      // Connection errors arrive as several different types depending on the layer.
      throw EmployeeFailure.network;
    }
  }

  Map<String, dynamic> _details(Object? details) {
    if (details is Map<String, dynamic>) return details;
    if (details is String && details.isNotEmpty) {
      try {
        final decoded = jsonDecode(details);
        if (decoded is Map<String, dynamic>) return decoded;
      } on FormatException {
        return const {};
      }
    }
    return const {};
  }
}
