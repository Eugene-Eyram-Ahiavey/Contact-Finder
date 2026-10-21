import 'package:flutter/material.dart';
import 'package:evangelism_caller_id/database/app_database.dart';
import 'package:evangelism_caller_id/services/contact_importer.dart';
import 'package:evangelism_caller_id/utils/phone_number_normalizer.dart';

/// ImportNotesModal
///
/// A bottom-sheet / modal allowing evangelism team members to paste
/// lists copied directly from Apple Notes, WhatsApp, or Excel spreadsheets,
/// preview parsed contacts, fix issues, and save into local SQLite database.
class ImportNotesModal extends StatefulWidget {
  final AppDatabase database;
  final VoidCallback onImportCompleted;

  const ImportNotesModal({
    super.key,
    required this.database,
    required this.onImportCompleted,
  });

  @override
  State<ImportNotesModal> createState() => _ImportNotesModalState();
}

class _ImportNotesModalState extends State<ImportNotesModal> {
  final TextEditingController _textController = TextEditingController();
  ImportBatchResult? _previewResult;
  bool _isSaving = false;
  String? _errorMessage;

  void _parsePastedText() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _errorMessage = 'Please paste some contact lines first.';
        _previewResult = null;
      });
      return;
    }

    final result = ContactImporter.parseText(text);
    setState(() {
      _previewResult = result;
      _errorMessage = null;
    });
  }

  Future<void> _confirmAndSave() async {
    if (_previewResult == null || _previewResult!.validContacts.isEmpty) return;

    setState(() => _isSaving = true);

    int savedCount = 0;
    int duplicateCount = 0;

    for (final contact in _previewResult!.validContacts) {
      try {
        await widget.database.insertContact(contact);
        savedCount++;
      } on DuplicatePhoneNumberException {
        duplicateCount++;
      } catch (e) {
        // Unexpected error
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
      widget.onImportCompleted();
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved $savedCount contacts${duplicateCount > 0 ? " ($duplicateCount existing skipped)" : ""}',
          ),
          backgroundColor: Colors.teal.shade700,
        ),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPreviewing = _previewResult != null;

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

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isPreviewing ? 'Preview Contacts' : 'Paste from Notes / Excel',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey.shade900,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (!isPreviewing) ...[
            Text(
              'Copy a list from Apple Notes, Google Keep, or Excel and paste it below. '
              'The app will automatically detect names, Ghana numbers (024...), locations, and notes.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 12),

            // Text input area
            Expanded(
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: 'e.g.\n'
                      'Kofi Mensah - 0244123456 - Tema\n'
                      'Ama Serwaa, 0551122334, Spintex\n'
                      'Pastor John: 0277889900: Madina\n',
                  hintStyle: TextStyle(color: Colors.grey.shade400),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ),

            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),

            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _parsePastedText,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Parse & Preview Contacts'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ] else ...[
            // Preview summary badges
            Row(
              children: [
                _buildBadge(
                  label: '${_previewResult!.validContacts.length} Valid',
                  color: Colors.teal,
                  icon: Icons.check_circle_outline,
                ),
                const SizedBox(width: 8),
                if (_previewResult!.skippedLines.isNotEmpty)
                  _buildBadge(
                    label: '${_previewResult!.skippedLines.length} Skipped',
                    color: Colors.orange,
                    icon: Icons.warning_amber_rounded,
                  ),
                const SizedBox(width: 8),
                if (_previewResult!.duplicateInBatch.isNotEmpty)
                  _buildBadge(
                    label: '${_previewResult!.duplicateInBatch.length} Duplicates',
                    color: Colors.redAccent,
                    icon: Icons.copy,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Preview List
            Expanded(
              child: ListView.builder(
                itemCount: _previewResult!.validContacts.length,
                itemBuilder: (context, index) {
                  final contact = _previewResult!.validContacts[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.indigo.shade50,
                        child: Text(
                          contact.name.isNotEmpty
                              ? contact.name[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: Colors.indigo.shade700,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        contact.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        PhoneNumberNormalizer.formatForDisplay(
                          contact.phoneNumber,
                        ),
                      ),
                      trailing: contact.location != null
                          ? Chip(
                              label: Text(
                                contact.location!,
                                style: const TextStyle(fontSize: 12),
                              ),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: Colors.grey.shade100,
                            )
                          : null,
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _previewResult = null),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Back to Edit'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _confirmAndSave,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: Text(
                      _isSaving
                          ? 'Saving...'
                          : 'Save ${_previewResult!.validContacts.length} Contacts',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBadge({
    required String label,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
