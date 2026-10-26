import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/date_range.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/repositories/repository.dart';

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.danger : AppColors.navy,
      behavior: SnackBarBehavior.floating,
    ));
}

Future<bool> confirm(BuildContext context, String title, String message,
    {String ok = 'Confirm', bool danger = false}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.danger, minimumSize: const Size(0, 40)) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return res ?? false;
}

/// Rebuilds [builder] with freshly loaded data whenever any repository
/// writes, or when [reloadKey] changes.
class Reloader<T> extends StatefulWidget {
  const Reloader({super.key, required this.load, required this.builder, this.reloadKey});

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final Object? reloadKey;

  @override
  State<Reloader<T>> createState() => _ReloaderState<T>();
}

class _ReloaderState<T> extends State<Reloader<T>> {
  T? _data;
  Object? _error;
  int _token = 0;
  DataChangeNotifier? _notifier;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final n = context.read<DataChangeNotifier>();
    if (n != _notifier) {
      _notifier?.removeListener(_reload);
      _notifier = n..addListener(_reload);
      _reload();
    }
  }

  @override
  void didUpdateWidget(covariant Reloader<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadKey != widget.reloadKey) _reload();
  }

  Future<void> _reload() async {
    final token = ++_token;
    try {
      final d = await widget.load();
      if (mounted && token == _token) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && token == _token) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _notifier?.removeListener(_reload);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _data == null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Error: $_error')));
    }
    if (_data == null) return const Center(child: CircularProgressIndicator());
    return widget.builder(context, _data as T);
  }
}

class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.required = false,
    this.allowZero = true,
    this.onChanged,
    this.helper,
  });

  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final bool required;
  final bool allowZero;
  final ValueChanged<String>? onChanged;
  final String? helper;

  static const maxPaisa = 100000000 * 100; // Rs 10 crore sanity limit

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(
        labelText: label,
        prefixText: '${Money.symbol} ',
        prefixIcon: icon == null ? null : Icon(icon),
        helperText: helper,
      ),
      onChanged: onChanged,
      validator: (v) {
        if ((v == null || v.trim().isEmpty)) return required ? 'Required' : null;
        final p = Money.tryParse(v);
        if (p == null) return 'Enter a valid amount (max 2 decimals)';
        if (p > maxPaisa) return 'Amount looks too large';
        if (!allowZero && p == 0) return 'Amount must be more than 0';
        return null;
      },
    );
  }
}

class DateField extends StatelessWidget {
  const DateField({super.key, required this.value, required this.onChanged, this.label = 'Date'});
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final now = DateTime.now();
        final d = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(now.year - 5),
          lastDate: now,
        );
        if (d != null) onChanged(d);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.event)),
        child: Text(displayDate(toDbDate(value))),
      ),
    );
  }
}

class TimeField extends StatelessWidget {
  const TimeField({super.key, required this.value, required this.onChanged, required this.label});
  final String value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final parts = value.split(':');
        final initial = parts.length == 2
            ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0)
            : TimeOfDay.now();
        final t = await showTimePicker(context: context, initialTime: initial);
        if (t != null) {
          onChanged('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.schedule)),
        child: Text(value.isEmpty ? '--:--' : value),
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, required this.child, this.trailing, this.padding});
  final String? title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(children: [
                  Expanded(
                    child: Text(title!,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.navy)),
                  ),
                  ?trailing,
                ]),
              ),
            child,
          ],
        ),
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.subtitle,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 4))),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.navy)),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Period chips (24h, 1W, 1M, 3M, 6M, 12M, custom).
class PeriodSelector extends StatelessWidget {
  const PeriodSelector({super.key, required this.period, required this.range, required this.onChanged});

  final Period period;
  final DateRange range;
  final void Function(Period, DateRange) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final p in Period.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(p.label),
                    avatar: p == Period.custom ? const Icon(Icons.date_range, size: 16) : null,
                    selected: p == period,
                    selectedColor: AppColors.orange,
                    labelStyle: TextStyle(
                      color: p == period ? Colors.white : AppColors.navy,
                      fontWeight: FontWeight.w600,
                    ),
                    showCheckmark: false,
                    onSelected: (_) async {
                      if (p == Period.custom) {
                        final now = DateTime.now();
                        final r = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(now.year - 5),
                          lastDate: now,
                          initialDateRange: DateTimeRange(start: range.start, end: range.end),
                        );
                        if (r != null) onChanged(p, DateRange(dateOnly(r.start), dateOnly(r.end)));
                      } else {
                        onChanged(p, DateRange.forPeriod(p));
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(range.label, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
      ],
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          ]),
        ),
      );
}

/// Row of label + money value used in detail cards.
class MoneyRow extends StatelessWidget {
  const MoneyRow(this.label, this.paisa, {super.key, this.bold = false, this.color});
  final String label;
  final int paisa;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text(Money.format(paisa), style: style),
      ]),
    );
  }
}
