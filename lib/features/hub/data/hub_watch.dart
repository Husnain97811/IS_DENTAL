import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:is_dental/core/constants/views.dart';
import 'package:is_dental/features/cash/data/cash_repository.dart';

// ═══════════════════════════════════════════════════════════════════════════
//  Watch list — things an owner wants to know about but staff won't mention:
//  discounts, cancelled bills, removed payments, deleted expenses, price and
//  commission changes, who took the money and who signed in when.
//  Read from records the app already keeps, plus the activity record.
// ═══════════════════════════════════════════════════════════════════════════

enum HubChangeKind {
  invoiceCancelled,
  paymentRemoved,
  expenseDeleted,
  rateChanged,
  priceEdited,
  userRemoved,
  signInFailed,
}

class HubChange {
  const HubChange({
    required this.kind,
    required this.at,
    required this.title,
    required this.detail,
    required this.who,
    this.amount,
  });

  final HubChangeKind kind;
  final DateTime at;
  final String title, detail, who;
  final int? amount;
}

class HubDiscount {
  const HubDiscount({
    required this.at,
    required this.patient,
    required this.invoiceNo,
    required this.amount,
    required this.subtotal,
    required this.dentist,
    this.by = '',
  });

  final DateTime at;
  final String patient, invoiceNo, dentist;

  /// Who gave it — recorded from the phase O update on, '' before that.
  final String by;
  final int amount, subtotal;
  double get share => subtotal <= 0 ? 0 : amount / subtotal;
  bool get big => share >= .3;
}

class HubSignIns {
  const HubSignIns({
    required this.name,
    required this.count,
    required this.afterHours,
    required this.failed,
    required this.last,
    required this.devices,
  });

  final String name;
  final int count, afterHours, failed;
  final DateTime? last;
  final Set<String> devices;
}

class HubWatch {
  const HubWatch({
    required this.discountTotal,
    required this.discountCount,
    required this.billedTotal,
    required this.discountByDentist,
    required this.discounts,
    required this.cancelledCount,
    required this.cancelledTotal,
    required this.removedCount,
    required this.removedTotal,
    required this.deletedCount,
    required this.deletedTotal,
    required this.noShows,
    required this.cancelledVisits,
    required this.changes,
    required this.takenBy,
    required this.signIns,
    required this.failedSignIns,
    required this.afterHoursSignIns,
    required this.hubVisits,
  });

  final int discountTotal, discountCount, billedTotal;
  final List<({String name, int total, int count})> discountByDentist;

  /// Biggest discounts first.
  final List<HubDiscount> discounts;

  final int cancelledCount, cancelledTotal;
  final int removedCount, removedTotal;
  final int deletedCount, deletedTotal;
  final int noShows, cancelledVisits;

  /// Newest first.
  final List<HubChange> changes;

  /// Money received, by the staff member who recorded it.
  final List<({String name, int total, int count})> takenBy;

  final List<HubSignIns> signIns;
  final int failedSignIns, afterHoursSignIns;
  final List<ActivityEventRow> hubVisits;

  double get discountShare => billedTotal + discountTotal <= 0
      ? 0
      : discountTotal / (billedTotal + discountTotal);

  /// Items worth a red mark on the rail.
  int get flags =>
      discounts.where((d) => d.big).length +
      cancelledCount +
      removedCount +
      deletedCount +
      failedSignIns;
}

Future<HubWatch> loadHubWatch({
  required AppDatabase db,
  required List<Branch> branches,
  required String? branchId,
  required DateTime start,
  required DateTime end,
}) async {
  Expression<bool> inBranch(GeneratedColumn<String> c) =>
      branchId == null ? const Constant(true) : c.equals(branchId);

  // The activity record for the period, newest first. Not branch-filtered
  // here: an owner's lines carry no branch, but the discount, price or rate
  // they touched still belongs in a branch view.
  final allEvents =
      await (db.select(db.activityEvents)
            ..where(
              (t) =>
                  t.isDeleted.equals(false) &
                  t.happenedAt.isBiggerOrEqualValue(start) &
                  t.happenedAt.isSmallerThanValue(end),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.happenedAt)]))
          .get();
  List<String> parts(ActivityEventRow e) => e.detail.split('|');
  final discountBy = <String, String>{
    for (final e in allEvents.reversed)
      if (e.kind == 'discount_given') parts(e).first: e.userName,
  };

  // ── discounts: invoices whose adjustment took money off ──
  final discRows =
      await (db.select(db.invoices).join([
            innerJoin(
              db.patients,
              db.patients.id.equalsExp(db.invoices.patientId),
            ),
          ])..where(
            db.invoices.isDeleted.equals(false) &
                db.invoices.status.equals('cancelled').not() &
                db.invoices.adjustment.isBiggerThanValue(0) &
                db.invoices.issuedAt.isBiggerOrEqualValue(start) &
                db.invoices.issuedAt.isSmallerThanValue(end) &
                inBranch(db.invoices.branchId),
          ))
          .get();
  final apptIds = <int>{
    for (final r in discRows)
      if (r.readTable(db.invoices).appointmentId != null)
        r.readTable(db.invoices).appointmentId!,
  };
  final dentistOf = apptIds.isEmpty
      ? const <int, String>{}
      : {
          for (final a in await (db.select(
            db.appointments,
          )..where((t) => t.id.isIn(apptIds))).get())
            a.id: a.dentist.trim(),
        };
  final discounts = [
    for (final r in discRows)
      () {
        final i = r.readTable(db.invoices);
        return HubDiscount(
          at: i.issuedAt,
          patient: r.readTable(db.patients).fullName,
          invoiceNo: i.invoiceNo,
          amount: i.adjustment,
          subtotal: i.subtotal,
          dentist: i.appointmentId == null
              ? ''
              : (dentistOf[i.appointmentId] ?? ''),
          by: discountBy[i.invoiceNo] ?? '',
        );
      }(),
  ]..sort((a, b) => b.amount.compareTo(a.amount));
  final byDentist = <String, ({String name, int total, int count})>{};
  for (final d in discounts) {
    final name = d.dentist.isEmpty ? 'Not linked to a visit' : d.dentist;
    final k = d.dentist.isEmpty ? '' : dentistKey(d.dentist);
    final prev = byDentist[k];
    byDentist[k] = (
      name: prev?.name ?? name,
      total: (prev?.total ?? 0) + d.amount,
      count: (prev?.count ?? 0) + 1,
    );
  }

  final billed =
      await (db.select(db.invoices)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.status.equals('cancelled').not() &
                t.issuedAt.isBiggerOrEqualValue(start) &
                t.issuedAt.isSmallerThanValue(end) &
                inBranch(t.branchId),
          ))
          .get();

  final changes = <HubChange>[];

  // ── cancelled invoices ──
  final cancelled =
      await (db.select(db.invoices).join([
            innerJoin(
              db.patients,
              db.patients.id.equalsExp(db.invoices.patientId),
            ),
          ])..where(
            db.invoices.status.equals('cancelled') &
                db.invoices.cancelledAt.isBiggerOrEqualValue(start) &
                db.invoices.cancelledAt.isSmallerThanValue(end) &
                inBranch(db.invoices.branchId),
          ))
          .get();
  var cancelledTotal = 0;
  for (final r in cancelled) {
    final i = r.readTable(db.invoices);
    cancelledTotal += i.total;
    changes.add(
      HubChange(
        kind: HubChangeKind.invoiceCancelled,
        at: i.cancelledAt ?? i.updatedAt,
        title: 'Invoice ${i.invoiceNo} cancelled',
        detail: r.readTable(db.patients).fullName,
        who: i.cancelledBy ?? '',
        amount: i.total,
      ),
    );
  }

  // ── payments removed ──
  final removed =
      await (db.select(db.invoicePayments).join([
            innerJoin(
              db.invoices,
              db.invoices.id.equalsExp(db.invoicePayments.invoiceId),
            ),
            innerJoin(
              db.patients,
              db.patients.id.equalsExp(db.invoices.patientId),
            ),
          ])..where(
            db.invoicePayments.isDeleted.equals(true) &
                db.invoicePayments.deletedAt.isBiggerOrEqualValue(start) &
                db.invoicePayments.deletedAt.isSmallerThanValue(end) &
                inBranch(db.invoicePayments.branchId),
          ))
          .get();
  var removedTotal = 0;
  for (final r in removed) {
    final p = r.readTable(db.invoicePayments);
    removedTotal += p.amount;
    changes.add(
      HubChange(
        kind: HubChangeKind.paymentRemoved,
        at: p.deletedAt ?? p.updatedAt,
        title:
            'Payment removed · invoice ${r.readTable(db.invoices).invoiceNo}',
        detail:
            '${r.readTable(db.patients).fullName} · paid ${p.method}'
            '${(p.receivedByName ?? '').isEmpty ? '' : ', taken by ${p.receivedByName}'}',
        who: p.deletedByName ?? '',
        amount: p.amount,
      ),
    );
  }

  // ── expenses deleted ──
  final deleted =
      await (db.select(db.expenses)..where(
            (t) =>
                t.isDeleted.equals(true) &
                t.deletedAt.isBiggerOrEqualValue(start) &
                t.deletedAt.isSmallerThanValue(end) &
                inBranch(t.branchId),
          ))
          .get();
  var deletedTotal = 0;
  for (final e in deleted) {
    deletedTotal += e.amount;
    changes.add(
      HubChange(
        kind: HubChangeKind.expenseDeleted,
        at: e.deletedAt ?? e.updatedAt,
        title: 'Expense deleted',
        detail: [
          if ((e.description ?? '').trim().isNotEmpty) e.description!.trim(),
          if ((e.deleteReason ?? '').trim().isNotEmpty)
            'reason: ${e.deleteReason!.trim()}',
        ].join(' · '),
        who: e.deletedByName ?? '',
        amount: e.amount,
      ),
    );
  }

  String pct(String v) {
    final d = double.tryParse(v);
    return d == null ? v : '${d.toStringAsFixed(d % 1 == 0 ? 0 : 1)}%';
  }

  // ── commission rates changed ──
  final ratesLogged = <String>{};
  for (final e in allEvents.where((e) => e.kind == 'rate_changed')) {
    final p = parts(e);
    if (p.length < 3) continue;
    ratesLogged.add(dentistKey(p[0]));
    changes.add(
      HubChange(
        kind: HubChangeKind.rateChanged,
        at: e.happenedAt,
        title: 'Commission rate changed · ${p[0]}',
        detail: p[1].isEmpty
            ? 'set to ${pct(p[2])}'
            : '${pct(p[1])} → ${pct(p[2])}',
        who: e.userName,
      ),
    );
  }
  for (final r
      in await (db.select(db.dentistRates)..where(
            (t) =>
                t.updatedAt.isBiggerOrEqualValue(start) &
                t.updatedAt.isSmallerThanValue(end),
          ))
          .get()) {
    if (ratesLogged.contains(dentistKey(r.dentistName))) continue;
    changes.add(
      HubChange(
        kind: HubChangeKind.rateChanged,
        at: r.updatedAt,
        title: r.isDeleted
            ? 'Commission rate removed · ${r.dentistName}'
            : 'Commission rate set · ${r.dentistName}',
        detail: r.isDeleted
            ? ''
            : '${r.percent.toStringAsFixed(r.percent % 1 == 0 ? 0 : 1)}% of what their patients pay',
        who: '',
      ),
    );
  }

  // ── price list edits ──
  final pricesLogged = <String>{};
  for (final e in allEvents.where(
    (e) =>
        e.kind == 'price_changed' ||
        e.kind == 'procedure_added' ||
        e.kind == 'procedure_removed',
  )) {
    final p = parts(e);
    if (p.length < 3) continue;
    pricesLogged.add(p[0].trim().toLowerCase());
    changes.add(
      HubChange(
        kind: HubChangeKind.priceEdited,
        at: e.happenedAt,
        title: switch (e.kind) {
          'procedure_added' => 'Procedure added · ${p[0]}',
          'procedure_removed' => 'Procedure removed · ${p[0]}',
          _ => 'Price changed · ${p[0]}',
        },
        detail: switch (e.kind) {
          'procedure_added' => 'Rs ${p[2]}',
          'procedure_removed' => 'was Rs ${p[1]}',
          _ => 'Rs ${p[1]} → Rs ${p[2]}',
        },
        who: e.userName,
      ),
    );
  }
  for (final t
      in await (db.select(db.treatments)..where(
            (t) =>
                t.updatedAt.isBiggerOrEqualValue(start) &
                t.updatedAt.isSmallerThanValue(end),
          ))
          .get()) {
    if (pricesLogged.contains(t.name.trim().toLowerCase())) continue;
    changes.add(
      HubChange(
        kind: HubChangeKind.priceEdited,
        at: t.updatedAt,
        title: t.isDeleted
            ? 'Procedure removed · ${t.name}'
            : 'Procedure added or changed · ${t.name}',
        detail: t.isDeleted ? '' : 'Price now Rs ${t.price}',
        who: '',
      ),
    );
  }

  // ── staff logins removed ──
  for (final u
      in await (db.select(db.users)..where(
            (t) =>
                t.isDeleted.equals(true) &
                t.updatedAt.isBiggerOrEqualValue(start) &
                t.updatedAt.isSmallerThanValue(end),
          ))
          .get()) {
    changes.add(
      HubChange(
        kind: HubChangeKind.userRemoved,
        at: u.updatedAt,
        title: 'Staff login removed · ${u.fullName}',
        detail: u.role,
        who: '',
      ),
    );
  }

  // ── visits that didn't happen ──
  final visits =
      await (db.select(db.appointments)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.status.isIn(const ['noShow', 'cancelled']) &
                t.startsAt.isBiggerOrEqualValue(start) &
                t.startsAt.isSmallerThanValue(end) &
                inBranch(t.branchId),
          ))
          .get();

  // ── who took the money ──
  final pays =
      await (db.select(db.invoicePayments)..where(
            (t) =>
                t.isDeleted.equals(false) &
                t.paidAt.isBiggerOrEqualValue(start) &
                t.paidAt.isSmallerThanValue(end) &
                inBranch(t.branchId),
          ))
          .get();
  final taken = <String, ({String name, int total, int count})>{};
  for (final p in pays) {
    final taker = (p.receivedByName ?? '').trim();
    final name = taker.isEmpty ? 'Name not recorded' : taker;
    final prev = taken[name];
    taken[name] = (
      name: name,
      total: (prev?.total ?? 0) + p.amount,
      count: (prev?.count ?? 0) + 1,
    );
  }

  // ── sign-ins (from the activity record) ──
  final events = branchId == null
      ? allEvents
      : allEvents.where((e) => e.branchId == branchId).toList();

  // Opening hours of the branches in view: earliest open, latest close;
  // a weekday is "closed" only if every branch is closed then.
  final open = branches.isEmpty
      ? 9 * 60
      : branches.map((b) => b.openMinutes).reduce(math.min);
  final close = branches.isEmpty
      ? 21 * 60
      : branches.map((b) => b.closeMinutes).reduce(math.max);
  bool closedDay(int weekday) =>
      branches.isNotEmpty &&
      branches.every(
        (b) => b.closedDays
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .contains(weekday),
      );
  bool afterHours(DateTime t) {
    final m = t.hour * 60 + t.minute;
    // 30 minutes either side is normal opening-up and closing time
    return closedDay(t.weekday) || m < open - 30 || m > close + 30;
  }

  final people = <String, HubSignIns>{};
  var failed = 0, outside = 0;
  for (final e in events) {
    if (e.kind != 'sign_in' && e.kind != 'sign_in_failed') continue;
    final name = e.userName.isEmpty ? 'Unknown' : e.userName;
    final prev = people[name];
    final ok = e.kind == 'sign_in';
    final odd = ok && afterHours(e.happenedAt);
    if (!ok) {
      failed++;
      changes.add(
        HubChange(
          kind: HubChangeKind.signInFailed,
          at: e.happenedAt,
          title: 'Failed sign-in · "$name"',
          detail: [
            if (e.device.isNotEmpty) 'Computer ${e.device}',
            if (e.detail.isNotEmpty) e.detail,
          ].join(' · '),
          who: '',
        ),
      );
    }
    if (odd) outside++;
    people[name] = HubSignIns(
      name: name,
      count: (prev?.count ?? 0) + (ok ? 1 : 0),
      afterHours: (prev?.afterHours ?? 0) + (odd ? 1 : 0),
      failed: (prev?.failed ?? 0) + (ok ? 0 : 1),
      // events are newest first, so the first one seen is the latest
      last: prev?.last ?? (ok ? e.happenedAt : null),
      devices: {...?prev?.devices, if (e.device.isNotEmpty) e.device},
    );
  }

  changes.sort((a, b) => b.at.compareTo(a.at));
  int byTotal(
    ({String name, int total, int count}) a,
    ({String name, int total, int count}) b,
  ) => b.total.compareTo(a.total);

  return HubWatch(
    discountTotal: discounts.fold(0, (s, d) => s + d.amount),
    discountCount: discounts.length,
    billedTotal: billed.fold(0, (s, i) => s + i.total),
    discountByDentist: byDentist.values.toList()..sort(byTotal),
    discounts: discounts.take(10).toList(),
    cancelledCount: cancelled.length,
    cancelledTotal: cancelledTotal,
    removedCount: removed.length,
    removedTotal: removedTotal,
    deletedCount: deleted.length,
    deletedTotal: deletedTotal,
    noShows: visits.where((a) => a.status == 'noShow').length,
    cancelledVisits: visits.where((a) => a.status == 'cancelled').length,
    changes: changes.take(40).toList(),
    takenBy: taken.values.toList()..sort(byTotal),
    signIns: people.values.toList()..sort((a, b) => b.count.compareTo(a.count)),
    failedSignIns: failed,
    afterHoursSignIns: outside,
    hubVisits: events.where((e) => e.kind == 'hub_open').take(12).toList(),
  );
}
