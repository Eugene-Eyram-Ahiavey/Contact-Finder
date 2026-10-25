import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:qara/database/app_database.dart';
import 'package:qara/models/contact.dart';
import 'package:qara/models/interaction.dart';
import 'package:qara/services/phone_dialer_service.dart';
import 'package:qara/utils/phone_number_normalizer.dart';

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
  late Contact _contact;
  List<Interaction> _interactions = [];
  bool _isLoadingInteractions = true;

  @override
  void initState() {
    super.initState();
    _contact = widget.contact;
    _loadInteractions();
  }

  Future<void> _loadInteractions() async {
    final list = await widget.database.getInteractionsForContact(_contact.id);
    if (mounted) {
      setState(() {
        _interactions = list;
        _isLoadingInteractions = false;
      });
    }
  }

  Future<void> _showEditContactDialog() async {
    final nameController = TextEditingController(text: _contact.name);
    final phoneController = TextEditingController(text: _contact.phoneNumber);
    final locationController = TextEditingController(text: _contact.location ?? '');
    final notesController = TextEditingController(text: _contact.notes ?? '');

    String? validationError;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              title: const Text('Edit Evangelism Contact'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Full Name'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: 'Phone Number (e.g. 0244123456)',
                        errorText: validationError,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: locationController,
                      decoration: const InputDecoration(labelText: 'Location / Area'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Outreach Notes'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final rawPhone = phoneController.text.trim();
                    final normalized = PhoneNumberNormalizer.normalize(rawPhone);

                    if (normalized == null) {
                      setDialogState(() {
                        validationError = 'Please enter a valid phone number';
                      });
                      return;
                    }

                    // Check if another contact already has this phone number
                    final existing = await widget.database.findContactByPhoneNumber(rawPhone);
                    if (existing != null && existing.id != _contact.id) {
                      setDialogState(() {
                        validationError = 'Another contact already has this phone number';
                      });
                      return;
                    }

                    final updated = _contact.copyWith(
                      name: nameController.text.trim().isNotEmpty
                          ? nameController.text.trim()
                          : 'Unknown Contact',
                      phoneNumber: rawPhone,
                      normalizedPhoneNumber: normalized,
                      location: locationController.text.trim().isNotEmpty
                          ? locationController.text.trim()
                          : null,
                      notes: notesController.text.trim().isNotEmpty
                          ? notesController.text.trim()
                          : null,
                      updatedAt: DateTime.now(),
                    );

                    await widget.database.updateContact(updated);
                    if (ctx.mounted) {
                      Navigator.of(ctx).pop();
                    }
                    if (mounted) {
                      setState(() {
                        _contact = updated;
                      });
                      widget.onDataChanged();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Contact updated successfully')),
                      );
                    }
                  },
                  child: const Text('Save Changes'),
                ),
              ],
            );
          },
        );
      },
    );
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
                      contactId: _contact.id,
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
        content: Text('Are you sure you want to delete ${_contact.name}?'),
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
      await widget.database.deleteContact(_contact.id);
      if (mounted) {
        widget.onDataChanged();
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayPhone = PhoneNumberNormalizer.formatForDisplay(_contact.phoneNumber);

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
                  _contact.name.isNotEmpty ? _contact.name[0].toUpperCase() : '?',
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
                      _contact.name,
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      displayPhone,
                      style: TextStyle(color: Colors.indigo.shade600, fontWeight: FontWeight.w600),
                    ),
                    if (_contact.location != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _contact.location!,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: Colors.indigo),
                    onPressed: _showEditContactDialog,
                    tooltip: 'Edit Contact',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                    onPressed: _deleteContact,
                    tooltip: 'Delete Contact',
                  ),
                ],
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
                    final dialed = await PhoneDialerService.dial(_contact.phoneNumber);
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
          if (_contact.notes != null && _contact.notes!.isNotEmpty) ...[
            Text('Outreach Notes:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(_contact.notes!),
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
