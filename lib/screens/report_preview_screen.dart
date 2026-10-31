import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qara/models/contact.dart';
import 'package:qara/services/report_generator_service.dart';

/// ReportPreviewScreen
///
/// Full-screen modal for previewing, customizing, and sharing
/// outreach call reports. Features:
/// 1. Editable report title (pre-filled with Call Center name).
/// 2. Live preview of the formatted WhatsApp-style report.
/// 3. Status summary bar showing counts per category.
/// 4. Copy to clipboard for quick paste anywhere.
/// 5. Native OS share sheet (WhatsApp, Telegram, Email, SMS, etc.)
///    via share_plus or platform channels.
class ReportPreviewScreen extends StatefulWidget {
  final String callCenterName;
  final List<Contact> contacts;

  const ReportPreviewScreen({
    super.key,
    required this.callCenterName,
    required this.contacts,
  });

  @override
  State<ReportPreviewScreen> createState() => _ReportPreviewScreenState();
}

class _ReportPreviewScreenState extends State<ReportPreviewScreen> {
  late TextEditingController _titleController;
  bool _includePhoneNumbers = true;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.callCenterName);
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  String get _generatedReport => ReportGeneratorService.generateReport(
        title: _titleController.text.trim().isNotEmpty
            ? _titleController.text.trim()
            : widget.callCenterName,
        contacts: widget.contacts,
        includePhoneNumbers: _includePhoneNumbers,
      );

  Map<String, int> get _statusSummary =>
      ReportGeneratorService.getStatusSummary(widget.contacts);

  void _copyToClipboard({String message = 'Report copied to clipboard!'}) {
    Clipboard.setData(ClipboardData(text: _generatedReport));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.teal.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static const MethodChannel _platform =
      MethodChannel('com.mode.qara/caller_id');

  Future<void> _shareReport() async {
    try {
      final success =
          await _platform.invokeMethod<bool>('shareText', _generatedReport);
      if (success != true) {
        _copyToClipboard(
            message: 'Share sheet dismissed or unavailable. Copied to clipboard.');
      }
    } catch (e) {
      debugPrint('[Qara] shareReport error: $e');
      _copyToClipboard(
          message: 'Share error: $e. Copied to clipboard.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _statusSummary;
    final report = _generatedReport;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'Call Report',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.indigo.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Editable Title Section
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Report Title',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _titleController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'e.g. SWOLLEN SATURDAY CALL LIST',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: Colors.indigo.shade400, width: 1.5),
                    ),
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),

          // Status Summary Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Divider(color: Colors.grey.shade200, height: 1),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: summary.entries.map((entry) {
                    final isPending =
                        entry.key == ReportGeneratorService.pendingStatus;
                    final color =
                        isPending ? Colors.grey : _getStatusColor(entry.key);
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: color.withOpacity(0.3)),
                      ),
                      child: Text(
                        '${entry.key}: ${entry.value}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      'Total: ${widget.contacts.length} contacts',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Phone #s',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          height: 24,
                          width: 36,
                          child: Switch(
                            value: _includePhoneNumbers,
                            onChanged: (val) =>
                                setState(() => _includePhoneNumbers = val),
                            activeColor: Colors.indigo,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Live Report Preview
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  report,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    fontFamily: 'monospace',
                    color: Colors.grey.shade800,
                  ),
                ),
              ),
            ),
          ),

          // Action Buttons
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _copyToClipboard,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(color: Colors.indigo.shade300),
                      foregroundColor: Colors.indigo.shade700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _shareReport,
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Share Report'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade700,
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
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    final lower = status.toLowerCase();
    if (lower.contains('coming') ||
        lower.contains('confirm') ||
        lower.contains('yes')) {
      return Colors.green;
    }
    if (lower.contains('not coming') ||
        lower.contains('busy') ||
        lower.contains('sick') ||
        lower.contains('can\'t') ||
        lower.contains('cannot')) {
      return Colors.red;
    }
    if (lower.contains('no answer') ||
        lower.contains('unreachable') ||
        lower.contains('not reachable') ||
        lower.contains('didn\'t answer') ||
        lower.contains('not answering') ||
        lower.contains('cannot be reached')) {
      return Colors.orange;
    }
    if (lower.contains('wrong') ||
        lower.contains('invalid') ||
        lower.contains('incorrect')) {
      return Colors.deepPurple;
    }
    if (lower.contains('call back') ||
        lower.contains('call again') ||
        lower.contains('later')) {
      return Colors.blue;
    }
    if (lower.contains('not sure') || lower.contains('maybe')) {
      return Colors.amber;
    }
    return Colors.blueGrey;
  }
}
