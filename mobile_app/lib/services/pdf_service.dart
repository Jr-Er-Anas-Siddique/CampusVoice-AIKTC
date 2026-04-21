// lib/services/pdf_service.dart
//
// Generates formal complaint log / escalation document.
// REQUIRES in pubspec.yaml:
//   pdf: ^3.11.0
//   path_provider: ^2.1.3
//   share_plus: ^10.0.2

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/post_model.dart';
import '../models/comment_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PdfService {
  PdfService._();
  static final PdfService instance = PdfService._();

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<List<CommentModel>> _fetchComments(String id) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('complaints').doc(id)
          .collection('comments')
          .orderBy('createdAt').get();
      return snap.docs.map((d) => CommentModel.fromFirestore(d.data(), d.id)).toList();
    } catch (_) { return []; }
  }

  String _statusLabel(ComplaintStatus s) {
    switch (s) {
      case ComplaintStatus.pendingReview: return 'Pending Review';
      case ComplaintStatus.approved:      return 'Approved';
      case ComplaintStatus.underReview:   return 'Under Review';
      case ComplaintStatus.inProgress:    return 'In Progress';
      case ComplaintStatus.resolved:      return 'Resolved';
      case ComplaintStatus.rejected:      return 'Rejected';
      case ComplaintStatus.flagged:       return 'Flagged';
      default:                            return s.name;
    }
  }

  String _fmtDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2,'0')} '
      '${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][dt.month-1]} '
      '${dt.year}';

  String _fmtDateTime(DateTime dt) =>
      '${_fmtDate(dt)}, ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';

  // ── Main entry ────────────────────────────────────────────────────────────

  Future<void> generateAndShare({
    required BuildContext context,
    required PostModel post,
    required String reporterName,
    required String reporterRollNo,
    required String reporterDepartment,
  }) async {
    final comments = post.id != null ? await _fetchComments(post.id!) : <CommentModel>[];

    // ── Colours ──────────────────────────────────────────────────────────────
    const kNavy    = PdfColor.fromInt(0xFF1A237E);
    const kIndigo  = PdfColor.fromInt(0xFF3949AB);
    const kGreen   = PdfColor.fromInt(0xFF2E7D32);
    const kOrange  = PdfColor.fromInt(0xFFE65100);
    const kGrey1   = PdfColor.fromInt(0xFF424242); // dark text
    const kGrey2   = PdfColor.fromInt(0xFF757575); // mid text
    const kGrey3   = PdfColor.fromInt(0xFFBDBDBD); // light border
    const kBgLight = PdfColor.fromInt(0xFFF5F5F5);
    const kBgBlue  = PdfColor.fromInt(0xFFE8EAF6);
    const kBgGreen = PdfColor.fromInt(0xFFE8F5E9);
    const kBgOrange= PdfColor.fromInt(0xFFFFF3E0);

    // ── Widget helpers ────────────────────────────────────────────────────────

    pw.Widget divider() => pw.Container(
      height: 1, color: kGrey3, margin: const pw.EdgeInsets.symmetric(vertical: 8));

    pw.Widget sectionTitle(String n, String title) => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10, top: 4),
      padding: const pw.EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: const pw.BoxDecoration(
        color: kBgBlue,
        border: pw.Border(left: pw.BorderSide(color: kNavy, width: 4)),
      ),
      child: pw.Row(children: [
        pw.Container(
          width: 20, height: 20,
          decoration: const pw.BoxDecoration(color: kNavy, shape: pw.BoxShape.circle),
          child: pw.Center(
            child: pw.Text(n,
                style: pw.TextStyle(fontSize: 9, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Text(title,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: kNavy)),
      ]),
    );

    pw.Widget kv(String k, String v, {PdfColor? vColor}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(
          width: 140,
          child: pw.Text(k, style: pw.TextStyle(fontSize: 8.5, color: kGrey2))),
        pw.SizedBox(width: 4),
        pw.Expanded(
          child: pw.Text(v,
              style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: vColor ?? kGrey1))),
      ]),
    );

    pw.Widget box({required pw.Widget child, PdfColor bg = kBgLight, PdfColor border = kGrey3}) =>
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: bg,
            border: pw.Border.all(color: border),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: child,
        );

    pw.Widget urlRow(String label, String url) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Container(
          width: 4, height: 4,
          margin: const pw.EdgeInsets.only(top: 3, right: 6),
          decoration: const pw.BoxDecoration(color: kIndigo, shape: pw.BoxShape.circle),
        ),
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 8, color: kGrey2)),
            pw.Text(url,
                style: pw.TextStyle(fontSize: 7.5, color: kIndigo,
                    decoration: pw.TextDecoration.underline)),
          ]),
        ),
      ]),
    );

    // ── Build PDF ─────────────────────────────────────────────────────────────
    final pdf = pw.Document(
      title: post.isChallenged
          ? 'Resolution Challenge — ${post.title}'
          : 'Complaint Log — ${post.title}',
      author: 'CampusVoice AIKTC',
    );

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 32, 40, 32),

      // ── Header ───────────────────────────────────────────────────────────
      header: (ctx) => pw.Column(children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('AI-KHAN TECHNICAL CAMPUS',
                  style: pw.TextStyle(fontSize: 7, color: kGrey2, letterSpacing: 1.5)),
              pw.SizedBox(height: 2),
              pw.Text('CampusVoice',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: kNavy)),
              pw.Text('Grievance Management System',
                  style: pw.TextStyle(fontSize: 8, color: kGrey2)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: pw.BoxDecoration(
                  color: post.isChallenged ? kOrange : kNavy,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  post.isChallenged
                      ? 'ESCALATION DOCUMENT'
                      : 'OFFICIAL COMPLAINT LOG',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white, letterSpacing: 0.5)),
              ),
              pw.SizedBox(height: 5),
              if (post.id != null)
                pw.Text('Ref: ${post.id!.substring(0, 14).toUpperCase()}',
                    style: pw.TextStyle(fontSize: 8, color: kGrey2)),
              pw.Text('Generated: ${_fmtDateTime(DateTime.now())}',
                  style: pw.TextStyle(fontSize: 8, color: kGrey2)),
            ]),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Container(height: 2, color: kNavy),
        pw.SizedBox(height: 4),
      ]),

      // ── Footer ───────────────────────────────────────────────────────────
      footer: (ctx) => pw.Column(children: [
        pw.Container(height: 0.5, color: kGrey3),
        pw.SizedBox(height: 4),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('CampusVoice AIKTC — Confidential Complaint Record',
              style: pw.TextStyle(fontSize: 7, color: kGrey2)),
          pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 7, color: kGrey2)),
        ]),
      ]),

      build: (ctx) => [

        // ── ESCALATION NOTICE ───────────────────────────────────────────────
        if (post.isChallenged) ...[
          box(
            bg: kBgOrange,
            border: kOrange,
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Row(children: [
                pw.Container(
                  width: 14, height: 14,
                  decoration: const pw.BoxDecoration(color: kOrange, shape: pw.BoxShape.circle),
                  child: pw.Center(
                    child: pw.Text('!',
                        style: pw.TextStyle(fontSize: 9, color: PdfColors.white,
                            fontWeight: pw.FontWeight.bold)),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Text('FORMAL RESOLUTION CHALLENGE',
                    style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: kOrange)),
              ]),
              pw.SizedBox(height: 6),
              pw.Text(
                'This document constitutes an official challenge to the resolution provided by the '
                'committee for the complaint referenced above. The student named herein asserts that '
                'the resolution is inadequate and requests review by the appropriate authority. '
                'This document must be presented at the college office, Dean\'s office, or Grievance Cell '
                'along with any supporting evidence.',
                style: pw.TextStyle(fontSize: 8.5, color: kGrey1, lineSpacing: 1.8),
              ),
              if (post.challengedAt != null) ...[
                pw.SizedBox(height: 6),
                pw.Row(children: [
                  pw.Text('Date of Challenge: ',
                      style: pw.TextStyle(fontSize: 8.5, color: kGrey2)),
                  pw.Text(_fmtDateTime(post.challengedAt!),
                      style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: kOrange)),
                ]),
              ],
            ]),
          ),
          pw.SizedBox(height: 14),
        ],

        // ── SECTION 1: COMPLAINT INFORMATION ───────────────────────────────
        sectionTitle('1', 'COMPLAINT INFORMATION'),
        box(
          child: pw.Column(children: [
            kv('Complaint Reference', post.id?.toUpperCase() ?? 'N/A'),
            kv('Title', post.title),
            kv('Category', post.category.label),
            kv('Current Status', _statusLabel(post.status),
                vColor: post.status == ComplaintStatus.resolved ? kGreen
                    : post.status == ComplaintStatus.flagged ? kOrange : kNavy),
            kv('Location', [post.building, if (post.floor != null) post.floor!].join(', ')),
            if (post.roomNumber != null) kv('Room / Area', post.roomNumber!),
            kv('Assigned Committee', post.assignedCommittee ?? 'Not yet assigned'),
            kv('Date Submitted', _fmtDateTime(post.createdAt)),
            kv('Last Updated', _fmtDateTime(post.updatedAt)),
            kv('Visibility', post.isPublic ? 'Public' : 'Private (Sensitive)'),
            kv('Supports Received', '${post.supportCount}'),
            kv('Comments', '${post.commentCount}'),
            kv('Evidence Files',
                '${post.imageUrls.length} image(s), ${post.videoPaths.length} video(s)'),
            if (post.isChallenged)
              kv('Resolution Status', 'CHALLENGED BY STUDENT', vColor: kOrange),
          ]),
        ),
        pw.SizedBox(height: 8),
        box(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('COMPLAINT DESCRIPTION',
                style: pw.TextStyle(fontSize: 8.5, color: kGrey2, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 5),
            pw.Text(post.description,
                style: pw.TextStyle(fontSize: 9, color: kGrey1, lineSpacing: 2)),
          ]),
        ),
        pw.SizedBox(height: 14),

        // ── SECTION 2: REPORTER ─────────────────────────────────────────────
        sectionTitle('2', 'REPORTED BY'),
        box(
          child: pw.Column(children: [
            kv('Full Name', reporterName),
            kv('Roll Number', reporterRollNo),
            kv('Department', reporterDepartment),
            kv('Institute Email', post.userEmail),
          ]),
        ),
        pw.SizedBox(height: 14),

        // ── SECTION 3: STUDENT EVIDENCE MEDIA ──────────────────────────────
        if (post.imageUrls.isNotEmpty || post.videoPaths.isNotEmpty) ...[
          sectionTitle('3', 'STUDENT EVIDENCE MEDIA'),
          box(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(
                'The following media files were submitted by the student as evidence. '
                'Click the links to view online (requires internet connection).',
                style: pw.TextStyle(fontSize: 8.5, color: kGrey2, lineSpacing: 1.5),
              ),
              if (post.imageUrls.isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Text('Evidence Images (${post.imageUrls.length})',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: kGrey1)),
                pw.SizedBox(height: 4),
                ...post.imageUrls.asMap().entries.map((e) =>
                    urlRow('Image ${e.key + 1}', e.value)),
              ],
              if (post.videoPaths.isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Text('Evidence Videos (${post.videoPaths.length})',
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: kGrey1)),
                pw.SizedBox(height: 4),
                ...post.videoPaths.asMap().entries.map((e) =>
                    urlRow('Video ${e.key + 1}', e.value)),
              ],
            ]),
          ),
          pw.SizedBox(height: 14),
        ],

        // ── SECTION 4: COMMITTEE RESOLUTION ────────────────────────────────
        if (post.status == ComplaintStatus.resolved) ...[
          sectionTitle('4', 'COMMITTEE RESOLUTION'),
          box(
            bg: kBgGreen,
            border: const PdfColor.fromInt(0xFFA5D6A7),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              if (post.resolutionNote != null) ...[
                pw.Text('RESOLUTION MESSAGE FROM COMMITTEE',
                    style: pw.TextStyle(fontSize: 8.5, color: kGrey2, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 5),
                pw.Text(post.resolutionNote!,
                    style: pw.TextStyle(fontSize: 9, color: kGrey1, lineSpacing: 2)),
              ],
              if (post.resolutionImages.isNotEmpty) ...[
                pw.SizedBox(height: 10),
                pw.Text('RESOLUTION EVIDENCE (${post.resolutionImages.length} image(s))',
                    style: pw.TextStyle(fontSize: 8.5, color: kGrey2, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 3),
                pw.Text(
                  'Images uploaded by committee confirming resolution. '
                  'View in app or use links below.',
                  style: pw.TextStyle(fontSize: 8, color: kGrey2, lineSpacing: 1.5),
                ),
                pw.SizedBox(height: 5),
                ...post.resolutionImages.asMap().entries.map((e) =>
                    urlRow('Resolution Image ${e.key + 1}', e.value)),
              ],
            ]),
          ),
          pw.SizedBox(height: 14),
        ],

        // ── SECTION 5: STATUS TIMELINE ──────────────────────────────────────
        sectionTitle('5', 'COMPLETE STATUS TIMELINE'),
        pw.Column(
          children: post.statusHistory.asMap().entries.map((entry) {
            final i = entry.key;
            final e = entry.value;
            final isLast = i == post.statusHistory.length - 1;
            return pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 0),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Column(children: [
                  pw.Container(
                    width: 10, height: 10,
                    margin: const pw.EdgeInsets.only(top: 1, right: 10),
                    decoration: pw.BoxDecoration(
                      color: isLast ? kNavy : kIndigo,
                      shape: pw.BoxShape.circle,
                    ),
                  ),
                  if (!isLast)
                    pw.Container(
                      width: 1, height: 28,
                      margin: const pw.EdgeInsets.only(right: 10),
                      color: kGrey3,
                    ),
                ]),
                pw.Expanded(
                  child: pw.Padding(
                    padding: pw.EdgeInsets.only(bottom: isLast ? 0 : 4),
                    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(_statusLabel(e.status),
                              style: pw.TextStyle(
                                  fontSize: 9, fontWeight: pw.FontWeight.bold, color: kNavy)),
                          pw.Text(_fmtDateTime(e.changedAt),
                              style: pw.TextStyle(fontSize: 8, color: kGrey2)),
                        ],
                      ),
                      if (e.note != null)
                        pw.Text(e.note!,
                            style: pw.TextStyle(fontSize: 8.5, color: kGrey1, lineSpacing: 1.5)),
                      pw.Text('Action by: ${e.changedBy}',
                          style: pw.TextStyle(fontSize: 8, color: kGrey2)),
                    ]),
                  ),
                ),
              ]),
            );
          }).toList(),
        ),
        pw.SizedBox(height: 14),

        // ── SECTION 6: COMMENTS ─────────────────────────────────────────────
        if (comments.isNotEmpty) ...[
          sectionTitle('6', 'PUBLIC COMMENTS (${comments.length})'),
          pw.Column(
            children: comments.asMap().entries.map((entry) {
              final i = entry.key;
              final c = entry.value;
              return pw.Container(
                margin: pw.EdgeInsets.only(bottom: i < comments.length - 1 ? 6 : 0),
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: i.isEven ? kBgLight : PdfColors.white,
                  border: pw.Border.all(color: kGrey3),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(c.userName,
                          style: pw.TextStyle(
                              fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: kNavy)),
                      pw.Text(_fmtDateTime(c.createdAt),
                          style: pw.TextStyle(fontSize: 7.5, color: kGrey2)),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(c.text,
                      style: pw.TextStyle(fontSize: 8.5, color: kGrey1, lineSpacing: 1.6)),
                ]),
              );
            }).toList(),
          ),
          pw.SizedBox(height: 14),
        ],

        // ── SECTION 7: STUDENT DECLARATION (escalation only) ───────────────
        if (post.isChallenged) ...[
          sectionTitle('7', 'STUDENT DECLARATION'),
          box(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(
                'I, $reporterName, Roll Number $reporterRollNo, Department of $reporterDepartment, '
                'a student of AI-Khan Technical Campus, Navi Mumbai, hereby declare that I am not '
                'satisfied with the resolution provided by the committee for the complaint referenced '
                'in this document. I formally request a review by the appropriate authority '
                '(Dean\'s office or Grievance Cell) and request that this matter be addressed '
                'within a reasonable time frame.',
                style: pw.TextStyle(fontSize: 8.5, color: kGrey1, lineSpacing: 2.2),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'I affirm that all information provided in this document is true and accurate '
                'to the best of my knowledge.',
                style: pw.TextStyle(fontSize: 8.5, color: kGrey1, lineSpacing: 2),
              ),
            ]),
          ),
          pw.SizedBox(height: 28),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Container(width: 180, height: 0.5, color: kGrey2),
                pw.SizedBox(height: 5),
                pw.Text('Student Signature',
                    style: pw.TextStyle(fontSize: 8, color: kGrey2)),
                pw.SizedBox(height: 2),
                pw.Text(reporterName,
                    style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                pw.Text(reporterRollNo,
                    style: pw.TextStyle(fontSize: 8.5, color: kGrey1)),
                pw.Text(reporterDepartment,
                    style: pw.TextStyle(fontSize: 8, color: kGrey2)),
              ]),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Container(width: 150, height: 0.5, color: kGrey2),
                pw.SizedBox(height: 5),
                pw.Text('Date',
                    style: pw.TextStyle(fontSize: 8, color: kGrey2)),
                pw.SizedBox(height: 2),
                pw.Text(
                  post.challengedAt != null
                      ? _fmtDateTime(post.challengedAt!)
                      : _fmtDateTime(DateTime.now()),
                  style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
              ]),
            ],
          ),
          pw.SizedBox(height: 20),
          divider(),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text(
              'This is a system-generated document from CampusVoice AIKTC. '
              'For verification contact: aiktc.edu.in',
              style: pw.TextStyle(fontSize: 7.5, color: kGrey2),
              textAlign: pw.TextAlign.center,
            ),
          ),
        ],

      ],
    ));

    // ── Save & share ──────────────────────────────────────────────────────────
    final bytes = await pdf.save();
    final dir = await getTemporaryDirectory();
    final shortId = (post.id ?? DateTime.now().millisecondsSinceEpoch.toString())
        .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
        .substring(0, 10);
    final label = post.isChallenged ? 'escalation' : 'complaint_log';
    final file = File('${dir.path}/campusvoice_${label}_$shortId.pdf');
    await file.writeAsBytes(bytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: post.isChallenged
          ? 'Resolution Challenge — ${post.title}'
          : 'Complaint Log — ${post.title}',
      text: post.isChallenged
          ? 'Formal escalation document. Filed: ${_fmtDateTime(DateTime.now())}.'
          : 'Complaint log: ${post.title}.',
    );
  }
}
