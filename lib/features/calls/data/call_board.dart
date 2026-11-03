import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:is_dental/core/constants/views.dart';
import 'package:is_dental/cloud/data/sync_engine.dart';

import 'live_appointments.dart';
import 'patient_call.dart';

/// Everything the Call patients dialog, the appointment cards and (Phase B)
/// the reception screen need: today's calls, and whether the live
/// connection is up.
class CallBoard {
  const CallBoard({
    required this.day,
    required this.calls,
    required this.ready,
    required this.live,
    required this.reachable,
  });

  factory CallBoard.initial(String day) => CallBoard(
    day: day,
    calls: const [],
    ready: false,
    live: false,
    reachable: true,
  );

  final String day;
  final List<PatientCall> calls;

  /// Today's calls have been loaded at least once.
  final bool ready;

  /// The live channel is subscribed.
  final bool live;

  /// The last internet check reached the cloud.
  final bool reachable;

  /// Calling is allowed only while this is true. When false the UI shows
  /// only the WiFi-with-exclamation icon.
  bool get online => ready && live && reachable;

  CallBoard copyWith({
    String? day,
    List<PatientCall>? calls,
    bool? ready,
    bool? live,
    bool? reachable,
  }) => CallBoard(
    day: day ?? this.day,
    calls: calls ?? this.calls,
    ready: ready ?? this.ready,
    live: live ?? this.live,
    reachable: reachable ?? this.reachable,
  );
}

/// Keeps one live channel per computer for today's calls AND appointment
/// changes, so a booking or Mark arrived on one PC (or a booking from the
/// owner phone) shows on every other PC within a second or two.
///
/// Logins changed on another computer or the owner phone arrive the same
/// way, so a new staff member can sign in within seconds.
///
/// Runs on EVERY cloud plan — appointments travel through it on Basic too;
/// patient calls only exist on a plan with patient call. Started from the
/// top bar, so it runs from start-up on every screen. Every time the
/// channel (re)connects or the internet comes back it catches up: today's
/// calls, plus a quick patients + appointments sync, so nothing changed
/// while a computer was offline is missed.
class CallBoardController extends Notifier<CallBoard> {
  RealtimeChannel? _ch;
  Timer? _ping, _dayTimer, _catchUp;
  String? _clinicId;
  int _gen = 0;

  SupabaseClient get _sb => Supabase.instance.client;

  @override
  CallBoard build() {
    // every cloud plan: appointments must be live on Basic too
    final on = ref.watch(entitlementsProvider.select((e) => e.sync));
    final g = ++_gen;
    ref.onDispose(() => _stop(g));
    if (on) Future.microtask(() => _start(g));
    return CallBoard.initial(callDay(DateTime.now()));
  }

  bool _alive(int g) => g == _gen;

  void _set(int g, CallBoard Function(CallBoard s) f) {
    if (_alive(g)) state = f(state);
  }

  Future<void> _start(int g) async {
    if (!_alive(g)) return;
    final db = ref.read(appDatabaseProvider);
    final cloud = ref.read(cloudServiceProvider);
    _clinicId = await db.currentClinicId();
    if (_clinicId == null || !_alive(g)) return;
    try {
      await cloud.ensureSignedIn();
    } catch (_) {
      // offline at start-up — the channel keeps retrying, the ping notices
      // when the internet is back
    }
    if (!_alive(g)) return;

    _subscribe(g);
    _ping = Timer.periodic(const Duration(seconds: 20), (_) => _checkOnline(g));
    _dayTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final today = callDay(DateTime.now());
      if (_alive(g) && today != state.day) {
        _set(g, (s) => s.copyWith(day: today, calls: const [], ready: false));
        unawaited(_reload(g));
      }
    });
    await _checkOnline(g);
    await _reload(g);
  }

  void _subscribe(int g) {
    final cid = _clinicId!;
    final live = ref.read(liveAppointmentsProvider);
    final filter = PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'clinic_id',
      value: cid,
    );
    _ch = _sb
        .channel('dentos-live-$cid-$g')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'patient_calls',
          filter: filter,
          callback: (p) {
            if (!_alive(g) || p.newRecord.isEmpty) return;
            _merge(g, PatientCall.fromRow(p.newRecord));
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'appointments',
          filter: filter,
          callback: (p) {
            if (!_alive(g) || p.newRecord.isEmpty) return;
            unawaited(
              live.apply(p.newRecord, cid).then((more) {
                if (more) _catchUpSoon(g);
              }),
            );
          },
        )
        // a login added or changed on another computer or the owner phone:
        // fetch it now, so that person can sign in here straight away
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'users',
          filter: filter,
          callback: (_) {
            if (_alive(g)) _catchUpSoon(g);
          },
        )
        .subscribe((status, error) {
          if (!_alive(g)) return;
          final up = status == RealtimeSubscribeStatus.subscribed;
          _set(g, (s) => s.copyWith(live: up));
          // reconnected → fetch whatever was pressed while we were away
          if (up) {
            unawaited(_reload(g));
            _catchUpSoon(g);
          }
        });
  }

  /// A quick patients + appointments sync in a moment. Several reasons
  /// close together (five bookings arriving at once) make ONE run.
  void _catchUpSoon(int g) {
    if (!_alive(g) || (_catchUp?.isActive ?? false)) return;
    _catchUp = Timer(const Duration(seconds: 2), () {
      final cid = _clinicId;
      if (!_alive(g) || cid == null) return;
      unawaited(
        ref
            .read(syncEngineProvider)
            .syncAppointmentsNow(cid)
            .catchError((Object _) {}),
      );
    });
  }

  void _merge(int g, PatientCall c) {
    if (!_alive(g) || c.day != state.day) return;
    final list = [
      for (final x in state.calls)
        if (x.id != c.id) x,
      c,
    ]..sort((a, b) => a.seq.compareTo(b.seq));
    _set(g, (s) => s.copyWith(calls: list));
  }

  Future<void> _reload(int g) async {
    final cid = _clinicId;
    if (cid == null || !_alive(g)) return;
    // No patient call on this plan (Basic, or Standard without reception):
    // the channel is here for appointments only, there are no calls to load.
    if (!ref.read(entitlementsProvider).patientCall) {
      _set(g, (s) => s.copyWith(ready: true));
      return;
    }
    final day = state.day;
    try {
      final rows = await _sb
          .from('patient_calls')
          .select()
          .eq('clinic_id', cid)
          .eq('day', day)
          .order('seq', ascending: true)
          .timeout(const Duration(seconds: 8));
      if (!_alive(g) || state.day != day) return;
      final calls = [for (final r in (rows as List)) PatientCall.fromRow(r)]
        ..sort((a, b) => a.seq.compareTo(b.seq));
      _set(g, (s) => s.copyWith(calls: calls, ready: true, reachable: true));
    } catch (_) {
      _set(g, (s) => s.copyWith(reachable: false));
    }
  }

  /// A tiny read of the clinic row. Cheap, and the only reliable way to
  /// know the cloud is really reachable (a WiFi icon can be on with no
  /// internet behind it).
  Future<void> _checkOnline(int g) async {
    final cid = _clinicId;
    if (cid == null) return;
    var ok = false;
    try {
      await _sb
          .from('clinics')
          .select('id')
          .eq('id', cid)
          .limit(1)
          .timeout(const Duration(seconds: 6));
      ok = true;
    } catch (_) {}
    if (!_alive(g)) return;
    final wasDown = !state.reachable;
    _set(g, (s) => s.copyWith(reachable: ok));
    if (ok && wasDown) {
      // internet back → send what was booked offline, fetch what we missed
      unawaited(_reload(g));
      _catchUpSoon(g);
    }
  }

  void _stop(int g) {
    // Anything still in flight from this generation becomes a no-op.
    if (g == _gen) _gen++;
    _ping?.cancel();
    _dayTimer?.cancel();
    _catchUp?.cancel();
    _ping = null;
    _dayTimer = null;
    _catchUp = null;
    final ch = _ch;
    _ch = null;
    if (ch != null) {
      unawaited(_sb.removeChannel(ch).then((_) {}, onError: (_) {}));
    }
  }

  /// Checks the internet now — the dialog calls this when it opens.
  Future<void> refresh() async {
    final g = _gen;
    await _checkOnline(g);
    if (state.reachable) await _reload(g);
  }

  // ── actions — each returns null on success or a message to show ──

  /// Calls [p] to [queue]'s doctor.
  /// [by] overrides the signed-in name (the reception screen's automatic
  /// calls pass "DentOS (automatic)").
  Future<String?> callNext(
    DoctorQueue queue,
    WaitingPatient p, {
    String? by,
  }) async {
    final g = _gen;
    final cid = _clinicId;
    if (cid == null || !state.online) return _offlineMsg;
    final caller = by ?? ref.read(authControllerProvider)?.fullName;
    try {
      final row = await _sb
          .from('patient_calls')
          .insert({
            'clinic_id': cid,
            'branch_id': p.branchId,
            'dentist': queue.dentist,
            'day': state.day,
            'seq': queue.nextSeq,
            'appointment_uuid': p.appointmentUuid,
            'patient_name': p.name,
            'called_by': caller,
          })
          .select()
          .single()
          .timeout(const Duration(seconds: 8));
      _merge(g, PatientCall.fromRow(row));
      return null;
    } on PostgrestException catch (e) {
      await _reload(g);
      if (e.code == '23505') {
        return 'Someone else called a patient for ${queue.dentist} at the '
            'same moment. The list is up to date now.';
      }
      return 'Could not call ${p.name}: ${e.message}';
    } catch (_) {
      _set(g, (s) => s.copyWith(reachable: false));
      return _offlineMsg;
    }
  }

  /// Takes back [queue]'s current call: the patient before shows as on
  /// chair again, the current one returns to the waiting list.
  Future<String?> goBack(DoctorQueue queue) async {
    final g = _gen;
    final cur = queue.current;
    if (cur == null) return null;
    if (!state.online) return _offlineMsg;
    try {
      final rows = await _sb
          .from('patient_calls')
          .update({
            'undone': true,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', cur.id)
          .eq('undone', false)
          .select()
          .timeout(const Duration(seconds: 8));
      final list = rows as List;
      if (list.isEmpty) {
        await _reload(g);
        return 'That call was already changed on another computer. '
            'The list is up to date now.';
      }
      _merge(g, PatientCall.fromRow(list.first));
      return null;
    } on PostgrestException catch (e) {
      await _reload(g);
      return 'Could not go back: ${e.message}';
    } catch (_) {
      _set(g, (s) => s.copyWith(reachable: false));
      return _offlineMsg;
    }
  }

  /// Announces [queue]'s current patient again on the reception screen.
  Future<String?> repeat(DoctorQueue queue) async {
    final g = _gen;
    final cur = queue.current;
    if (cur == null) return null;
    if (!state.online) return _offlineMsg;
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final rows = await _sb
          .from('patient_calls')
          .update({'repeat_at': now, 'updated_at': now})
          .eq('id', cur.id)
          .select()
          .timeout(const Duration(seconds: 8));
      final list = rows as List;
      if (list.isNotEmpty) _merge(g, PatientCall.fromRow(list.first));
      return null;
    } catch (_) {
      _set(g, (s) => s.copyWith(reachable: false));
      return _offlineMsg;
    }
  }

  static const _offlineMsg =
      'No internet — nothing was changed. Try again when the connection '
      'is back.';
}

final callBoardProvider = NotifierProvider<CallBoardController, CallBoard>(
  CallBoardController.new,
);

/// Today's arrived patients on this computer. Follows the board's day, so
/// it rolls over at midnight with it.
final todayArrivalsProvider = StreamProvider<List<WaitingPatient>>((ref) {
  final day = ref.watch(callBoardProvider.select((b) => b.day));
  final p = day.split('-').map(int.parse).toList();
  return ref
      .watch(liveAppointmentsProvider)
      .watchArrivals(DateTime(p[0], p[1], p[2]));
});

/// May the signed-in person see the Call patients button?
final canCallPatientsProvider = Provider<bool>(
  (ref) =>
      ref.watch(entitlementsProvider.select((e) => e.patientCall)) &&
      ref.watch(canProvider(Perm.callPatients)),
);
