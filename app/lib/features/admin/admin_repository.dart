import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/format.dart';
import '../auth/auth_models.dart';
import 'admin_models.dart';

abstract class AdminRepository {
  String? get currentUserId;
  Future<List<AdminUser>> users();
  Future<List<Place>> places();
  Future<List<RamadanPeriod>> ramadanPeriods();
  Future<List<LedgerLine>> ledger();
  Future<List<WeekRow>> weekRows(DateTime start);
  Future<NewCredentials> createUser({required String fullName, required String username, String? department, required UserRole role, String? restaurantId});
  Future<void> updateUser(String id, {required String fullName, String? department, required UserRole role, Place? place});
  Future<int> liveBookingCount(String id);
  Future<String> resetPassword(String id);
  Future<void> setActive(String id, bool isActive);
  Future<void> addPlace({required String siteName, required String restaurantName});
  Future<void> topUp(List<String> employeeIds, int amount, String key);
  Future<RamadanImpact> previewRamadan(int hijriYear, DateTime start, DateTime end);
  Future<void> saveRamadan(int hijriYear, DateTime start, DateTime end, String key);
}

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => SupabaseAdminRepository(Supabase.instance.client),
);

/// New sites and restaurants take this zone until the institution needs another.
const defaultTimezone = 'Asia/Baghdad';

const _pageSize = 1000;

class SupabaseAdminRepository implements AdminRepository {
  SupabaseAdminRepository(this._client);

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  /// The server returns at most a page per request, and an institution can exceed that.
  Future<List<Map<String, dynamic>>> _allPages(Future<List<Map<String, dynamic>>> Function(int from, int to) page) async {
    final rows = <Map<String, dynamic>>[];
    while (true) {
      final next = await page(rows.length, rows.length + _pageSize - 1);
      rows.addAll(next);
      if (next.length < _pageSize) return rows;
    }
  }

  @override
  Future<List<AdminUser>> users() => _guard(() async {
        final rows = await _allPages((from, to) => _client
            .from('profiles')
            .select('id, username, full_name, department, role, restaurant_id, is_active, restaurants(name), wallets(available, held)')
            .order('full_name', ascending: true)
            .order('id', ascending: true)
            .range(from, to));
        return rows.map(AdminUser.fromRow).toList();
      });

  @override
  Future<List<Place>> places() => _guard(() async {
        final rows = await _client.from('restaurants').select('id, site_id, name, is_active, sites(name)').order('name', ascending: true);
        return rows.map(Place.fromRow).toList();
      });

  @override
  Future<List<RamadanPeriod>> ramadanPeriods() => _guard(() async {
        final rows = await _client.from('ramadan_periods').select().order('start_date', ascending: true);
        return rows.map(RamadanPeriod.fromRow).toList();
      });

  @override
  Future<List<LedgerLine>> ledger() => _guard(() async {
        final rows = await _client
            .from('wallet_transactions')
            .select('type, available_delta, note, created_at, wallets(profiles(full_name))')
            .inFilter('type', ['topup', 'adjustment'])
            .order('id', ascending: false)
            .limit(30);
        return rows.map(LedgerLine.fromRow).toList();
      });

  @override
  Future<List<WeekRow>> weekRows(DateTime start) => _guard(() async {
        final rows = await _allPages((from, to) => _client
            .from('bookings')
            .select('status, restaurant_id, meal_offerings!inner(service_date, period)')
            .gte('meal_offerings.service_date', isoDate(start))
            .lt('meal_offerings.service_date', isoDate(addDays(start, 7)))
            .order('id', ascending: true)
            .range(from, to));
        return rows.map(WeekRow.fromRow).toList();
      });

  @override
  Future<NewCredentials> createUser({required String fullName, required String username, String? department, required UserRole role, String? restaurantId}) =>
      _guard(() async {
        final data = await _invoke('create-user', {
          'full_name': fullName.trim(),
          'username': normalizeUsername(username),
          'department': department?.trim(),
          'role': role.name,
          'restaurant_id': role == UserRole.admin ? null : restaurantId,
        });
        return NewCredentials(username: data['username'] as String, password: data['temporary_password'] as String);
      });

  @override
  Future<void> updateUser(String id, {required String fullName, String? department, required UserRole role, Place? place}) => _guard(() async {
        final trimmed = department?.trim();
        await _client.from('profiles').update({
          'full_name': fullName.trim(),
          'department': trimmed == null || trimmed.isEmpty ? null : trimmed,
          'role': role.name,
          'site_id': role == UserRole.admin ? null : place?.siteId,
          'restaurant_id': role == UserRole.admin ? null : place?.id,
        }).eq('id', id);
      });

  @override
  Future<int> liveBookingCount(String id) => _guard(() async {
        final rows = await _client.from('bookings').select('id').eq('employee_id', id).eq('status', 'booked');
        return rows.length;
      });

  @override
  Future<String> resetPassword(String id) => _guard(() async {
        final data = await _invoke('reset-password', {'user_id': id});
        return data['temporary_password'] as String;
      });

  @override
  Future<void> setActive(String id, bool isActive) => _guard(() async {
        await _invoke('set-user-active', {'user_id': id, 'is_active': isActive});
      });

  @override
  Future<void> addPlace({required String siteName, required String restaurantName}) => _guard(() async {
        // Reuses a site of the same name, so a retry after a failure does not duplicate it.
        final existing = await _client.from('sites').select('id').eq('name', siteName.trim()).limit(1).maybeSingle();
        final site = existing ?? await _client.from('sites').insert({'name': siteName.trim()}).select('id').single();
        await _client.from('restaurants').insert({
          'site_id': site['id'],
          'name': restaurantName.trim(),
          'timezone': defaultTimezone,
        });
      });

  @override
  Future<void> topUp(List<String> employeeIds, int amount, String key) => _guard(() async {
        await _client.rpc('admin_top_up', params: {'p_employee_ids': employeeIds, 'p_amount': amount, 'p_note': null, 'p_key': key});
      });

  @override
  Future<RamadanImpact> previewRamadan(int hijriYear, DateTime start, DateTime end) => _guard(() async {
        final result = await _client.rpc('preview_ramadan_change', params: {
          'p_hijri_year': hijriYear,
          'p_start': isoDate(start),
          'p_end': isoDate(end),
        }) as Map<String, dynamic>;
        return RamadanImpact(offerings: (result['offerings'] as num).toInt(), bookings: (result['bookings_to_refund'] as num).toInt());
      });

  @override
  Future<void> saveRamadan(int hijriYear, DateTime start, DateTime end, String key) => _guard(() async {
        await _client.rpc('set_ramadan_period', params: {
          'p_hijri_year': hijriYear,
          'p_start': isoDate(start),
          'p_end': isoDate(end),
          'p_key': key,
        });
      });

  Future<Map<String, dynamic>> _invoke(String function, Map<String, dynamic> body) async {
    try {
      final response = await _client.functions.invoke(function, body: body);
      return response.data as Map<String, dynamic>;
    } on FunctionException catch (error) {
      final details = error.details;
      throw AdminFailure.fromCode(details is Map ? details['error'] as String? ?? '' : '');
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AdminFailure {
      rethrow;
    } on PostgrestException catch (error) {
      if (error.code == 'P0001') throw AdminFailure.fromCode(error.message);
      throw AdminFailure.unknown;
    } on AuthException {
      throw AdminFailure.network;
    } on Exception {
      // Connection errors arrive as several different types depending on the layer.
      throw AdminFailure.network;
    }
  }
}
