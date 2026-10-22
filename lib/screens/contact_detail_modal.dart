import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:evangelism_caller_id/database/app_database.dart';
import 'package:evangelism_caller_id/models/contact.dart';
import 'package:evangelism_caller_id/models/interaction.dart';
import 'package:evangelism_caller_id/services/phone_dialer_service.dart';
import 'package:evangelism_caller_id/utils/phone_number_normalizer.dart';

/// ContactDetailModal
///
/// Displays a contact's profile, full follow-up interaction history,
/// and lets evangelism workers log new outreach calls without overwriting past history.
class ContactDetailModal extends StatefulWidget {
  final Contact contact;
  final AppDatabase database;
  final VoidCallback onDataChanged;

  const ContactDetailModal({
    super.key,
    required this.contact,
    required this.database,
    required this.onDataChanged,
  });

  @override
  State<ContactDetailModal> createState() => _ContactDetailModalState();
}

class _ContactDetailModalState extends State<ContactDetailModal> {
  static const _uuid = Uuid();
  List<Interaction> _interactions = [];
  bool _isLoadingInteractions = true;

  @override
  void initState() {
    super.initState();
    _loadInteractions();
  }

  Future<void> _loadInteractions() async {
    final list = await widget.database.getInteractionsForContact(widget.contact.id);
    if (mounted) {
      setState(() {
        _interactions = list;
        _isLoadingInteractions = false;
      });
    }
  }

  Future<void> _showAddFollowUpDialog() async {
    String selectedOutcome = 'Conversation completed';
    final notesController = TextEditingController();

    final outcomes = [
      'Conversation completed',
      'Called; no answer',
      'Follow-up needed',
      'Visit planned',
      'Wrong number',
    ];

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Log Outreach Call / Interaction'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Outcome:'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedOutcome,
                    items: outcomes.map((o) {
                      return DropdownMenuItem(value: o, child: Text(o));
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedOutcome = val);
                      }
                    },
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Follow-up Notes:'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: notesController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'What did you discuss?',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final newInteraction = Interaction(
                      id: _uuid.v4(),
                      contactId: widget.contact.id,
                      date: DateTime.now(),
                      outcome: selectedOutcome,
                      notes: notesController.text.trim().isNotEmpty
                          ? notesController.text.trim()
                          : null,
                      createdAt: DateTime.now(),
                    );
                    await widget.database.addInteraction(newInteraction);
                    if (context.mounted) {
                      Navigator.of(ctx).pop();
                      _loadInteractions();
                      widget.onDataChanged();
                    }
                  },
                  child: const Text('Save Interaction'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteContact() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text('Are you sure you want to delete ${widget.contact.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.database.deleteContact(widget.contact.id);
      if (mounted) {
        widget.onDataChanged();
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayPhone = PhoneNumberNormalizer.formatForDisplay(widget.contact.phoneNumber);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header Profile
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.indigo.shade100,
                child: Text(
                  widget.contact.name.isNotEmpty ? widget.contact.name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo.shade800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.contact.name,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      displayPhone,
                      style: TextStyle(color: Colors.indigo.shade600, fontWeight: FontWeight.w600),
                    ),
                    if (widget.contact.location != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          widget.contact.location!,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: _deleteContact,
                tooltip: 'Delete Contact',
              ),
            ],
          ),

          // Action Buttons: Direct Call & Log Notes
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final dialed = await PhoneDialerService.dial(widget.contact.phoneNumber);
                    if (!dialed && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not open phone dialer on this device.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.phone, color: Colors.white, size: 20),
                  label: const Text(
                    'Call Contact',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  onPressed: _showAddFollowUpDialog,
                  icon: const Icon(Icons.note_add_outlined, size: 18),
                  label: const Text('Log Notes'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(),

          // General outreach notes
          if (widget.contact.notes != null && widget.contact.notes!.isNotEmpty) ...[
            Text('Outreach Notes:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(widget.contact.notes!),
            ),
            const SizedBox(height: 14),
          ],

          // Follow-up history header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Follow-up History (${_interactions.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              TextButton.icon(
                onPressed: _showAddFollowUpDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Log Call'),
              ),
            ],
          ),

          // Follow-up Timeline
          Expanded(
            child: _isLoadingInteractions
                ? const Center(child: CircularProgressIndicator())
                : _interactions.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history, size: 36, color: Colors.grey.shade400),
                            const SizedBox(height: 8),
                            Text(
                              'No follow-up calls logged yet.',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _interactions.length,
                        itemBuilder: (context, index) {
                          final item = _interactions[index];
                          final formattedDate =
                              '${item.date.day}/${item.date.month}/${item.date.year}';
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            elevation: 0,
                            color: Colors.grey.shade50,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(color: Colors.grey.shade200),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        item.outcome,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.indigo.shade800,
                                        ),
                                      ),
                                      Text(
                                        formattedDate,
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                      ),
                                    ],
                                  ),
                                  if (item.notes != null) ...[
                                    const SizedBox(height: 6),
                                    Text(item.notes!, style: const TextStyle(fontSize: 13)),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
