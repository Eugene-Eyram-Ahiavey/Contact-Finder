import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:evangelism_caller_id/database/app_database.dart';
import 'package:evangelism_caller_id/services/contact_importer.dart';
import 'package:evangelism_caller_id/utils/phone_number_normalizer.dart';

/// ImportNotesModal
///
/// Allows evangelism team members to import outreach contacts via:
/// 1. Picking CSV or Excel (.xlsx) spreadsheet files directly from device storage.
/// 2. Pasting raw text copied from Apple Notes, Google Keep, WhatsApp, or email.
///
/// Provides an interactive preview table where workers can review parsed contacts,
/// fix ambiguous numbers, and batch-save into the local SQLite database.
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
  bool _isLoadingFile = false;
  String? _errorMessage;
  String? _selectedFileName;

  void _parsePastedText() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _errorMessage = 'Please paste some contact lines or pick a file first.';
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

  Future<void> _pickSpreadsheetFile() async {
    setState(() {
      _isLoadingFile = true;
      _errorMessage = null;
    });

    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx', 'txt'],
      );

      if (files.isEmpty) {
        setState(() => _isLoadingFile = false);
        return;
      }

      final file = files.first;
      final extension = file.extension?.toLowerCase();
      _selectedFileName = file.name;
      final bytes = await file.readAsBytes();

      if (extension == 'xlsx') {
        final parsed = ContactImporter.parseExcelBytes(bytes);
        setState(() {
          _previewResult = parsed;
          _isLoadingFile = false;
        });
        return;
      }

      // Handle CSV or plain text
      final content = utf8.decode(bytes, allowMalformed: true);
      _textController.text = content;
      final parsed = ContactImporter.parseText(content);
      setState(() {
        _previewResult = parsed;
        _isLoadingFile = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingFile = false;
        _errorMessage = 'Failed to load file: $e';
      });
    }
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
      } catch (_) {
        // Continue saving remaining
      }
    }

    if (mounted) {
      setState(() => _isSaving = false);
      widget.onImportCompleted();
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Saved $savedCount contacts${duplicateCount > 0 ? " ($duplicateCount already saved, skipped)" : ""}',
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
      height: MediaQuery.of(context).size.height * 0.88,
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
                isPreviewing ? 'Preview Contacts' : 'Import Outreach Contacts',
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
              'Pick a CSV or Excel spreadsheet file, or paste your notes directly below. '
              'Names, Ghana phone numbers (024...), locations, and notes will be extracted automatically.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 12),

            // File Upload Action Banner
            InkWell(
              onTap: _isLoadingFile ? null : _pickSpreadsheetFile,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade600,
                        shape: BoxShape.circle,
                      ),
                      child: _isLoadingFile
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.upload_file, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedFileName ?? 'Upload Spreadsheet File (.csv, .xlsx)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade900,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Excel spreadsheets, Google Sheets exports, or CSV lists',
                            style: TextStyle(fontSize: 12, color: Colors.indigo.shade700),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.indigo),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: Divider(color: Colors.grey.shade300)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('OR PASTE TEXT', style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Expanded(child: Divider(color: Colors.grey.shade300)),
              ],
            ),
            const SizedBox(height: 10),

            // Text input area
            Expanded(
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                decoration: InputDecoration(
                  hintText: 'Paste rows here, e.g.\n'
                      'Kofi Mensah - 0244123456 - Tema - Prayed for healing\n'
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
              label: const Text('Parse & Preview Pasted Text'),
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
              child: ListView.separated(
                itemCount: _previewResult!.validContacts.length +
                    _previewResult!.skippedLines.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  if (index < _previewResult!.validContacts.length) {
                    final contact = _previewResult!.validContacts[index];
                    final displayPhone =
                        PhoneNumberNormalizer.formatForDisplay(contact.phoneNumber);
                    return ListTile(
                      dense: true,
                      leading: const CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.teal,
                        child: Icon(Icons.check, size: 16, color: Colors.white),
                      ),
                      title: Text(contact.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        '$displayPhone ${contact.location != null ? "• ${contact.location}" : ""}',
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _editPreviewContact(index),
                      ),
                    );
                  } else {
                    final skippedIndex = index - _previewResult!.validContacts.length;
                    final skipped = _previewResult!.skippedLines[skippedIndex];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.orange.shade100,
                        child: Icon(Icons.warning, size: 16, color: Colors.orange.shade800),
                      ),
                      title: Text(
                        skipped.rawLine,
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        skipped.reason,
                        style: const TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    );
                  }
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
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Icon(Icons.save_alt),
                    label: Text(_isSaving
                        ? 'Saving...'
                        : 'Import ${_previewResult!.validContacts.length} Contacts'),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _editPreviewContact(int index) {
    final contact = _previewResult!.validContacts[index];
    final nameCtrl = TextEditingController(text: contact.name);
    final phoneCtrl = TextEditingController(text: contact.phoneNumber);
    final locationCtrl = TextEditingController(text: contact.location ?? '');
    final notesCtrl = TextEditingController(text: contact.notes ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Contact Preview'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone (e.g. 0244123456)'),
                keyboardType: TextInputType.phone,
              ),
              TextField(
                controller: locationCtrl,
                decoration: const InputDecoration(labelText: 'Location / Area'),
              ),
              TextField(
                controller: notesCtrl,
                decoration: const InputDecoration(labelText: 'Notes'),
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
            onPressed: () {
              final norm = PhoneNumberNormalizer.normalize(phoneCtrl.text);
              if (norm == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid phone number format')),
                );
                return;
              }
              setState(() {
                _previewResult!.validContacts[index] = contact.copyWith(
                  name: nameCtrl.text.trim(),
                  phoneNumber: phoneCtrl.text.trim(),
                  normalizedPhoneNumber: norm,
                  location: locationCtrl.text.trim().isNotEmpty
                      ? locationCtrl.text.trim()
                      : null,
                  notes: notesCtrl.text.trim().isNotEmpty
                      ? notesCtrl.text.trim()
                      : null,
                );
              });
              Navigator.of(ctx).pop();
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }
}
