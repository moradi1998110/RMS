import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../employee/employee_models.dart';
import 'manager_models.dart';

abstract class ManagerRepository {
  Future<List<ManagerMeal>> meals();
  Future<void> saveMeal(MealDraft draft);
  Future<List<ScheduleRow>> schedules();

  /// Adds a meal to days of the week, inside any matching weekly schedule it already has.
  Future<void> addSchedule({required String mealId, required MealPeriod period, required bool isRamadan, required List<int> weekdays, required bool weekly});
  Future<void> removeDay(ScheduleRow schedule, int dayOfWeek);
  Future<int> copyLastWeek();
  Future<List<TimeRule>> timeRules();
  Future<(int, int)> saveTimeRule(TimeRule rule);
  Future<List<TodayMeal>> today();
  Future<List<TodayBooking>> bookingsOf(String offeringId);
  Future<int> cancelMeal(String offeringId, String reason, String key);
  Future<void> recordDelivery(String bookingId, String reason, String key);
  Future<ScanResult> redeemToken(String token, String key);
  Future<ScanResult> redeemCode(String code, String key);
  Future<ManagerWeek> week(DateTime start);

  /// Ratings sent during the seven days from [start].
  Future<List<MealRating>> ratings(DateTime start);
  String imageUrl(String path);
}

final managerRepositoryProvider = Provider<ManagerRepository>(
  (ref) => SupabaseManagerRepository(Supabase.instance.client),
);

/// The bucket's own limit is 300 KB. Photos are shrunk when picked, so few reach this.
const maxImageBytes = 300 * 1024;

class SupabaseManagerRepository implements ManagerRepository {
  SupabaseManagerRepository(this._client);

  final SupabaseClient _client;

  Future<String> _restaurantId() async {
    final row = await _client.from('profiles').select('restaurant_id').eq('id', _client.auth.currentUser!.id).single();
    return row['restaurant_id'] as String;
  }

  @override
  Future<List<ManagerMeal>> meals() => _guard(() async {
        final rows = await _client
            .from('meals')
            .select('id, name, description, image_path, price, has_salad, has_soft_drink, has_juice, has_vegetables, is_active')
            .order('name', ascending: true);
        return rows.map(ManagerMeal.fromRow).toList();
      });

  @override
  Future<void> saveMeal(MealDraft draft) => _guard(() async {
        final restaurantId = await _restaurantId();
        var imagePath = draft.imagePath;
        final image = draft.newImage;
        if (image != null) {
          final isPng = image.length > 1 && image[0] == 0x89 && image[1] == 0x50;
          final path = '$restaurantId/${const Uuid().v4()}.${isPng ? 'png' : 'jpg'}';
          await _client.storage.from('meal-images').uploadBinary(
                path,
                image,
                fileOptions: FileOptions(contentType: isPng ? 'image/png' : 'image/jpeg'),
              );
          imagePath = path;
        }
        final values = {
          'name': draft.name.trim(),
          'description': draft.description.trim(),
          'price': draft.price,
          'has_salad': draft.hasSalad,
          'has_soft_drink': draft.hasSoftDrink,
          'has_juice': draft.hasJuice,
          'has_vegetables': draft.hasVegetables,
          'is_active': draft.isActive,
          'image_path': imagePath,
        };
        if (draft.id == null) {
          await _client.from('meals').insert({...values, 'restaurant_id': restaurantId});
        } else {
          await _client.from('meals').update(values).eq('id', draft.id!);
        }
      });

  @override
  Future<List<ScheduleRow>> schedules() => _guard(() async {
        final rows = await _client
            .from('schedules')
            .select('id, meal_id, period, season, weekdays, repeat_type, start_date, end_date, meals(name)')
            .eq('is_active', true)
            .order('created_at', ascending: true);
        return rows.map(ScheduleRow.fromRow).toList();
      });

  @override
  Future<void> addSchedule({required String mealId, required MealPeriod period, required bool isRamadan, required List<int> weekdays, required bool weekly}) =>
      _guard(() async {
        final today = dayOf(DateTime.now());
        final season = isRamadan ? 'ramadan' : 'normal';
        final existing = weekly
            ? await _client
                .from('schedules')
                .select('id, weekdays')
                .eq('is_active', true)
                .eq('meal_id', mealId)
                .eq('period', period.name)
                .eq('season', season)
                .eq('repeat_type', 'weekly')
                .isFilter('end_date', null)
                .limit(1)
                .maybeSingle()
            : null;
        if (existing != null) {
          final merged = {...(existing['weekdays'] as List).cast<int>(), ...weekdays}.toList()..sort();
          await _client.from('schedules').update({'weekdays': merged}).eq('id', existing['id'] as String);
        } else {
          await _client.from('schedules').insert({
            'restaurant_id': await _restaurantId(),
            'meal_id': mealId,
            'period': period.name,
            'season': season,
            'weekdays': weekdays,
            'repeat_type': weekly ? 'weekly' : 'one_week',
            'start_date': isoDate(today),
            'end_date': weekly ? null : isoDate(addDays(today, 6)),
          });
        }
        await _client.rpc('publish_schedule');
      });

  @override
  Future<void> removeDay(ScheduleRow schedule, int dayOfWeek) => _guard(() async {
        final left = schedule.weekdays.where((day) => day != dayOfWeek).toList();
        await _client
            .from('schedules')
            .update(left.isEmpty ? {'is_active': false} : {'weekdays': left})
            .eq('id', schedule.id);
      });

  @override
  Future<int> copyLastWeek() => _guard(() async {
        final copies = copiesFromLastWeek(await schedules(), dayOf(DateTime.now()));
        if (copies.isEmpty) return 0;
        final restaurantId = await _restaurantId();
        await _client.from('schedules').insert([
          for (final copy in copies)
            {
              'restaurant_id': restaurantId,
              'meal_id': copy.mealId,
              'period': copy.period.name,
              'season': copy.isRamadan ? 'ramadan' : 'normal',
              'weekdays': copy.weekdays,
              'repeat_type': 'one_week',
              'start_date': isoDate(copy.start),
              'end_date': copy.end == null ? null : isoDate(copy.end!),
            },
        ]);
        await _client.rpc('publish_schedule');
        return copies.length;
      });

  @override
  Future<List<TimeRule>> timeRules() => _guard(() async {
        final rows = await _client.from('time_defaults').select();
        return rows.map(TimeRule.fromRow).toList();
      });

  String _timeText(TimeOfDay time) => '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:00';

  @override
  Future<(int, int)> saveTimeRule(TimeRule rule) => _guard(() async {
        final result = await _client.rpc('set_meal_times', params: {
          'p_period': rule.period.name,
          'p_book_day_offset': rule.bookDay,
          'p_book_time': _timeText(rule.book),
          'p_cancel_day_offset': rule.cancelDay,
          'p_cancel_time': _timeText(rule.cancel),
          'p_pickup_from_day_offset': rule.fromDay,
          'p_pickup_from_time': _timeText(rule.from),
          'p_pickup_until_day_offset': rule.untilDay,
          'p_pickup_until_time': _timeText(rule.until),
        }) as Map<String, dynamic>;
        return ((result['updated_offerings'] as num).toInt(), (result['kept_booked_offerings'] as num).toInt());
      });

  @override
  Future<List<TodayMeal>> today() => _guard(() async {
        // By pickup time, not service date: a suhoor dated tomorrow is collected tonight.
        final start = dayOf(DateTime.now());
        final offerings = await _client
            .from('meal_offerings')
            .select('id, period, pickup_from, pickup_until, meals(name), bookings(status)')
            .eq('status', 'open')
            .gte('pickup_from', start.toUtc().toIso8601String())
            .lt('pickup_from', addDays(start, 1).toUtc().toIso8601String())
            .order('pickup_from', ascending: true);
        return offerings.map((row) {
          final statuses = (row['bookings'] as List).map((booking) => (booking as Map<String, dynamic>)['status']).toList();
          int count(String status) => statuses.where((value) => value == status).length;
          return TodayMeal(
            offeringId: row['id'] as String,
            name: (row['meals'] as Map<String, dynamic>)['name'] as String,
            period: MealPeriod.values.byName(row['period'] as String),
            pickupFrom: DateTime.parse(row['pickup_from'] as String).toLocal(),
            pickupUntil: DateTime.parse(row['pickup_until'] as String).toLocal(),
            waiting: count('booked'),
            collected: count('picked_up'),
            notCollected: count('no_show'),
          );
        }).toList();
      });

  @override
  Future<List<TodayBooking>> bookingsOf(String offeringId) => _guard(() async {
        final rows = await _client
            .from('bookings')
            .select('id, status, profiles!bookings_employee_id_fkey(full_name)')
            .eq('offering_id', offeringId)
            .inFilter('status', ['booked', 'picked_up', 'no_show']);
        return rows.map(TodayBooking.fromRow).toList()..sort((a, b) => a.employeeName.compareTo(b.employeeName));
      });

  @override
  Future<int> cancelMeal(String offeringId, String reason, String key) => _guard(() async {
        final result = await _client.rpc('cancel_offering', params: {'p_offering_id': offeringId, 'p_reason': reason.trim(), 'p_key': key}) as Map<String, dynamic>;
        return (result['refunded_bookings'] as num).toInt();
      });

  @override
  Future<void> recordDelivery(String bookingId, String reason, String key) => _guard(() async {
        await _client.rpc('record_manual_delivery', params: {'p_booking_id': bookingId, 'p_reason': reason.trim(), 'p_key': key});
      });

  @override
  Future<ScanResult> redeemToken(String token, String key) => _guard(() async {
        final result = await _client.rpc('redeem_pickup', params: {'p_token': token, 'p_key': key}) as Map<String, dynamic>;
        return ScanResult.fromJson(result);
      });

  @override
  Future<ScanResult> redeemCode(String code, String key) => _guard(() async {
        final result = await _client.rpc('redeem_short_code', params: {'p_code': code, 'p_key': key}) as Map<String, dynamic>;
        return ScanResult.fromJson(result);
      });

  @override
  Future<ManagerWeek> week(DateTime start) => _guard(() async {
        // Counted on the server: a few hundred rows instead of every booking of the week.
        final rows = await _client.rpc('booking_week_counts', params: {'p_start': isoDate(start)}) as List;
        return ManagerWeek.from(start, [for (final row in rows) ManagerWeekRow.fromRow(row as Map<String, dynamic>)]);
      });

  @override
  Future<List<MealRating>> ratings(DateTime start) => _guard(() async {
        final rows = await _client.rpc('meal_ratings_between', params: {
          'p_from': start.toUtc().toIso8601String(),
          'p_until': addDays(start, 7).toUtc().toIso8601String(),
        }) as List;
        return [for (final row in rows) MealRating.fromRow(row as Map<String, dynamic>)];
      });

  @override
  String imageUrl(String path) => _client.storage.from('meal-images').getPublicUrl(path);

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (error) {
      if (error.code == 'P0001') throw ManagerFailure.fromCode(error.message);
      throw ManagerFailure.unknown;
    } on StorageException {
      throw const ManagerFailure('تعذّر رفع الصورة. حاول مرة أخرى، أو احفظ الوجبة بلا صورة.');
    } on AuthException {
      throw ManagerFailure.network;
    } on Exception {
      // Connection errors arrive as several different types depending on the layer.
      throw ManagerFailure.network;
    }
  }
}

/// Lets tests pick a photo without the phone's camera or gallery.
typedef PhotoPicker = Future<Uint8List?> Function(bool fromCamera);
