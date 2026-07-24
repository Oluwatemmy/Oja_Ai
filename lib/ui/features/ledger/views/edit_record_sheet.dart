import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../data/repositories/ledger_repository.dart';
import '../../../../domain/models/ledger_entry.dart';
import '../../../core/theme.dart';
import '../../customer/views/customer_profile_view.dart';

/// Modal edit sheet for one ledger record. Fields: item, party, amount,
/// type toggle. Actions: Save, Delete, See customer.
class EditRecordSheet extends StatefulWidget {
  const EditRecordSheet({
    super.key,
    required this.entry,
    required this.ledger,
  });

  final LedgerEntry entry;
  final LedgerRepository ledger;

  static Future<void> show(BuildContext context, LedgerEntry entry) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => EditRecordSheet(
        entry: entry,
        ledger: LedgerRepositoryReader.of(context),
      ),
    );
  }

  @override
  State<EditRecordSheet> createState() => _EditRecordSheetState();
}

class _EditRecordSheetState extends State<EditRecordSheet> {
  late final TextEditingController _itemCtrl;
  late final TextEditingController _partyCtrl;
  late final TextEditingController _amountCtrl;
  late EntryType _type;

  @override
  void initState() {
    super.initState();
    _itemCtrl = TextEditingController(text: widget.entry.item);
    _partyCtrl = TextEditingController(text: widget.entry.party);
    _amountCtrl = TextEditingController(text: widget.entry.amount.toString());
    _type = widget.entry.type;
  }

  @override
  void dispose() {
    _itemCtrl.dispose();
    _partyCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 46,
                height: 5,
                decoration: BoxDecoration(
                  color: OjaColors.ink.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text('Edit record', style: OjaText.number(size: 22)),
            const SizedBox(height: 4),
            Text(_dateLabel(widget.entry.createdAt),
                style: OjaText.body(size: 15)),
            const SizedBox(height: 22),
            _label('What was sold or taken'),
            _field(_itemCtrl, hint: 'e.g. 2 crate egg'),
            const SizedBox(height: 14),
            _label('Person'),
            _field(_partyCtrl, hint: 'e.g. Mama Alex'),
            const SizedBox(height: 14),
            _label('Amount (₦)'),
            _field(
              _amountCtrl,
              hint: '0',
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            const SizedBox(height: 18),
            _label('Type'),
            _TypeToggle(
              type: _type,
              onChanged: (t) => setState(() => _type = t),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _save,
              style: FilledButton.styleFrom(
                backgroundColor: OjaColors.navy,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('Save changes',
                  style: OjaText.body(
                      size: 18,
                      weight: FontWeight.w800,
                      color: OjaColors.cream)),
            ),
            const SizedBox(height: 10),
            if (widget.entry.party.toLowerCase() != 'cash sale')
              OutlinedButton.icon(
                onPressed: _openCustomer,
                icon: const Icon(Icons.person_search_rounded,
                    color: OjaColors.navy),
                label: Text('See ${widget.entry.party} history',
                    style: OjaText.body(
                        size: 16,
                        weight: FontWeight.w700,
                        color: OjaColors.navy)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: OjaColors.navy, width: 2),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _confirmDelete,
              icon: const Icon(Icons.delete_outline_rounded,
                  color: OjaColors.red),
              label: Text('Delete dis record',
                  style: OjaText.body(
                      size: 16,
                      weight: FontWeight.w700,
                      color: OjaColors.red)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount < 0) {
      _snack('Amount must be a whole naira number.');
      return;
    }
    final item = _itemCtrl.text.trim();
    final party = _partyCtrl.text.trim();
    if (item.isEmpty) {
      _snack('Item can\'t be empty.');
      return;
    }
    await widget.ledger.editEntry(
      widget.entry.id,
      item: item,
      party: party.isEmpty ? 'Cash sale' : party,
      amount: amount,
      type: _type,
    );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Delete dis record?', style: OjaText.number(size: 20)),
        content: Text(
          'You go lose "${widget.entry.item}" (₦${widget.entry.amount}). '
          'This no fit undo.',
          style: OjaText.body(size: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Keep',
                style: OjaText.body(
                    size: 16,
                    weight: FontWeight.w700,
                    color: OjaColors.ink)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: OjaColors.red),
            child: Text('Delete',
                style: OjaText.body(
                    size: 16,
                    weight: FontWeight.w700,
                    color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.ledger.deleteEntry(widget.entry.id);
    if (mounted) Navigator.of(context).pop();
  }

  void _openCustomer() {
    Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          CustomerProfileView(partyName: widget.entry.party),
    ));
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 4),
        child: Text(text.toUpperCase(),
            style: OjaText.body(
              size: 13,
              weight: FontWeight.w800,
              color: OjaColors.ink,
            ).copyWith(letterSpacing: 0.6)),
      );

  Widget _field(
    TextEditingController controller, {
    required String hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: OjaText.body(size: 17, color: OjaColors.navy),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: OjaText.body(size: 16, color: OjaColors.ink),
        filled: true,
        fillColor: OjaColors.cream,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  static String _dateLabel(DateTime t) => '${t.day}/${t.month}/${t.year}';
}

class _TypeToggle extends StatelessWidget {
  const _TypeToggle({required this.type, required this.onChanged});
  final EntryType type;
  final ValueChanged<EntryType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _TypePill(
            active: type == EntryType.moneyIn,
            label: 'Money enta',
            color: OjaColors.green,
            onTap: () => onChanged(EntryType.moneyIn),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _TypePill(
            active: type == EntryType.owe,
            label: 'Dem owe',
            color: OjaColors.red,
            onTap: () => onChanged(EntryType.owe),
          ),
        ),
      ],
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({
    required this.active,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final bool active;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? color : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: Text(
              label,
              style: OjaText.body(
                size: 16,
                weight: FontWeight.w800,
                color: active ? Colors.white : color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cheap helper so the modal has access to the ledger without prop-drilling.
class LedgerRepositoryReader {
  static LedgerRepository of(BuildContext context) {
    return context.read<LedgerRepository>();
  }
}
