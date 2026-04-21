// lib/features/feed/presentation/pages/complaint_detail_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../models/post_model.dart';
import '../../../../models/comment_model.dart';
import '../../../../services/social_service.dart';
import '../../../../services/auth_service.dart';
import 'feed_page.dart' show FeedMediaCarousel;
import '../../../../services/pdf_service.dart';
import '../../../../main.dart' show AppColors;

class ComplaintDetailPage extends StatefulWidget {
  final PostModel post;
  const ComplaintDetailPage({super.key, required this.post});

  @override
  State<ComplaintDetailPage> createState() => _ComplaintDetailPageState();
}

class _ComplaintDetailPageState extends State<ComplaintDetailPage> {
  final TextEditingController _commentController = TextEditingController();
  bool _isSubmittingComment = false;

  String get _uid => AuthService.instance.currentUser?.uid ?? '';
  String get _userName =>
      AuthService.instance.currentUser?.displayName ?? 'Student';

  // Fetches reporter details for PDF
  Future<Map<String, String>> _getReporterDetails() async {
    String name = AuthService.instance.currentUser?.displayName ?? 'Student';
    String rollNo = (AuthService.instance.currentUser?.email ?? '').split('@').first.toUpperCase();
    String dept = 'N/A';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users').doc(_uid).get();
      if (doc.exists) {
        name = doc.data()?['fullName'] ?? name;
        final tag = (doc.data()?['departmentTag'] ?? '').toString().toLowerCase();
        const deptMap = {
          'co': 'Computer Engineering', 'ce': 'Civil Engineering',
          'me': 'Mechanical Engineering', 'ee': 'Electrical Engineering',
          'it': 'Information Technology', 'ai': 'AI & Data Science',
          'ds': 'Data Science', 'et': 'E&TC Engineering',
          'bit': 'B.Sc. IT', 'bca': 'BCA',
        };
        dept = deptMap[tag] ?? tag.toUpperCase();
      }
    } catch (_) {}
    return {'name': name, 'rollNo': rollNo, 'dept': dept};
  }

  void _showPdfGenerating() {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Row(children: [
        SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
        SizedBox(width: 10),
        Text('Generating PDF...'),
      ]),
      duration: Duration(seconds: 60),
      behavior: SnackBarBehavior.floating,
    ));
  }

  // Called from "Download Complaint Log" — no Firestore update, just PDF
  Future<void> _downloadPdf(PostModel post) async {
    final details = await _getReporterDetails();
    if (!mounted) return;
    _showPdfGenerating();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PdfService.instance.generateAndShare(
        context: context,
        post: post,
        reporterName: details['name']!,
        reporterRollNo: details['rollNo']!,
        reporterDepartment: details['dept']!,
      );
      messenger.hideCurrentSnackBar();
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text('Failed to generate PDF: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // Called from "Challenge Resolution" — updates Firestore FIRST, then generates PDF
  Future<void> _challengeResolution(PostModel post) async {
    // Confirm dialog — use context before any await
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Challenge Resolution?',
            style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
        content: const Text(
          'This will mark the complaint as "Challenged" — visible to all students and the committee. '
          'A PDF escalation document will be generated for you to present at the college office.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6B35),
              foregroundColor: Colors.white,
            ),
            child: const Text('Challenge & Download PDF'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Capture messenger before any async gap
    final messenger = ScaffoldMessenger.of(context);

    final details = await _getReporterDetails();
    if (!mounted) return;

    _showPdfGenerating();

    try {
      final now = DateTime.now();
      final newEntry = StatusHistoryEntry(
        status: post.status,
        changedAt: now,
        changedBy: details['name']!,
        note: 'Resolution challenged by student — escalated to college office',
      );
      final updatedHistory = [...post.statusHistory, newEntry];

      await FirebaseFirestore.instance
          .collection('complaints')
          .doc(post.id)
          .update({
        'isChallenged': true,
        'challengedAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'statusHistory': updatedHistory.map((e) => e.toMap()).toList(),
      });

      final challengedPost = post.copyWith(
        isChallenged: true,
        challengedAt: now,
        statusHistory: updatedHistory,
      );

      // context is safe here — PdfService only uses it to call Navigator.push
      // which is guarded by mounted check before this point
      if (!mounted) return;
      await PdfService.instance.generateAndShare(
        context: context,
        post: challengedPost,
        reporterName: details['name']!,
        reporterRollNo: details['rollNo']!,
        reporterDepartment: details['dept']!,
      );

      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(
        content: Text('Resolution challenged. PDF generated.'),
        backgroundColor: Color(0xFFFF6B35),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
        content: Text('Failed: $e'),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  void _openFullscreenImage(BuildContext ctx, List<String> urls, int index) {
    Navigator.of(ctx).push(MaterialPageRoute(
      builder: (_) => _FullscreenImageViewer(urls: urls, initialIndex: index),
    ));
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    // Dismiss keyboard immediately
    FocusScope.of(context).unfocus();
    setState(() => _isSubmittingComment = true);
    try {
      await SocialService.instance.addComment(
        complaintId: widget.post.id!,
        userId: _uid,
        userName: _userName,
        text: text,
      );
      _commentController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmittingComment = false);
    }
  }

  Color _statusColor(ComplaintStatus s) {
    switch (s) {
      case ComplaintStatus.pendingReview: return Colors.orange;
      case ComplaintStatus.approved:      return Colors.blue;
      case ComplaintStatus.underReview:   return Colors.blueGrey;
      case ComplaintStatus.inProgress:    return Colors.blue;
      case ComplaintStatus.resolved:      return Colors.green;
      case ComplaintStatus.rejected:      return Colors.red;
      case ComplaintStatus.flagged:       return Colors.deepOrange;
      default:                            return Colors.grey;
    }
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
      default:                            return 'Draft';
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Complaint Details',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Main card ──────────────────────────────────────────
                  Container(
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header — avatar + name + time
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: const Color(0xFF1A237E),
                                child: Text(
                                  post.userName.isNotEmpty
                                      ? post.userName[0].toUpperCase()
                                      : 'S',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(post.userName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15)),
                                    Text(
                                      '${post.building}  •  ${_timeAgo(post.createdAt)}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade500),
                                    ),
                                  ],
                                ),
                              ),
                              // Status badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: _statusColor(post.status)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: _statusColor(post.status)
                                          .withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  _statusLabel(post.status),
                                  style: TextStyle(
                                      color: _statusColor(post.status),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Category + title + description
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(post.category.icon,
                                      style: const TextStyle(fontSize: 13)),
                                  const SizedBox(width: 4),
                                  Text(post.category.label,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.indigo.shade400,
                                          fontWeight: FontWeight.w600)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(post.title,
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF1A237E))),
                              const SizedBox(height: 6),
                              Text(post.description,
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey.shade700,
                                      height: 1.5)),
                            ],
                          ),
                        ),

                        // Location + floor
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                          child: Row(
                            children: [
                              Icon(Icons.location_on_outlined,
                                  size: 15, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text(
                                [
                                  post.building,
                                  if (post.floor != null) post.floor!,
                                  if (post.roomNumber != null) post.roomNumber!,
                                ].join(', '),
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey.shade600),
                              ),
                              if (post.isOnCampus == true) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.verified_rounded,
                                    size: 14, color: Colors.green.shade500),
                                const SizedBox(width: 2),
                                Text('GPS verified',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.green.shade600,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ],
                          ),
                        ),

                        // Committee
                        if (post.assignedCommittee != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                            child: Row(
                              children: [
                                Icon(Icons.group_outlined,
                                    size: 15, color: Colors.grey.shade500),
                                const SizedBox(width: 4),
                                Text('Assigned: ${post.assignedCommittee}',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade600)),
                              ],
                            ),
                          ),

                        // Media
                        if (post.imageUrls.isNotEmpty ||
                            post.videoPaths.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          FeedMediaCarousel(
                              imageUrls: post.imageUrls,
                              videoPaths: post.videoPaths),
                        ],

                        // ── Action bar ───────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: Row(
                            children: [
                              // Support button
                              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                                stream: FirebaseFirestore.instance
                                    .collection('complaints')
                                    .doc(post.id)
                                    .collection('supporters')
                                    .doc(_uid)
                                    .snapshots(),
                                builder: (context, snap) {
                                  final supported = snap.data?.exists ?? false;
                                  return GestureDetector(
                                    onTap: () =>
                                        SocialService.instance.toggleSupport(
                                      complaintId: post.id!,
                                      userId: _uid,
                                    ),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: supported
                                            ? const Color(0xFF1A237E)
                                            : Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(24),
                                        border: Border.all(
                                            color: const Color(0xFF1A237E)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            supported
                                                ? Icons.thumb_up_rounded
                                                : Icons.thumb_up_alt_outlined,
                                            size: 17,
                                            color: supported
                                                ? Colors.white
                                                : const Color(0xFF1A237E),
                                          ),
                                          const SizedBox(width: 6),
                                          // Live support count
                                          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                                            stream: FirebaseFirestore.instance
                                                .collection('complaints')
                                                .doc(post.id)
                                                .snapshots(),
                                            builder: (context, countSnap) {
                                              final count = countSnap.hasData
                                                  ? ((countSnap.data!.data()?['supportCount'] ?? post.supportCount) as int)
                                                  : post.supportCount;
                                              return Text(
                                                '$count Support${count == 1 ? '' : 's'}',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: supported
                                                      ? Colors.white
                                                      : const Color(0xFF1A237E),
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),

                              const SizedBox(width: 12),

                              // Comment count pill
                              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                                stream: FirebaseFirestore.instance
                                    .collection('complaints')
                                    .doc(post.id)
                                    .snapshots(),
                                builder: (context, snap) {
                                  final count = snap.hasData
                                      ? ((snap.data!.data()?['commentCount'] ?? post.commentCount) as int)
                                      : post.commentCount;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.chat_bubble_outline_rounded,
                                            size: 17,
                                            color: Colors.grey.shade600),
                                        const SizedBox(width: 6),
                                        Text('$count Comment${count == 1 ? '' : 's'}',
                                            style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.grey.shade600)),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // ── Status Timeline ────────────────────────────────────
                  if (post.statusHistory.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Timeline',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A237E))),
                          const SizedBox(height: 12),
                          // Non-owners: hide flagged and pendingReview entries
                          ...() {
                            final isOwner = post.userId == _uid;
                            final visible = post.statusHistory.where((e) {
                              if (isOwner) return true;
                              return e.status != ComplaintStatus.flagged &&
                                     e.status != ComplaintStatus.pendingReview;
                            }).toList();
                            return visible.asMap().entries.map((entry) {
                              final i = entry.key;
                              final e = entry.value;
                              final isLast = i == visible.length - 1;
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Column(children: [
                                    Container(
                                      width: 12, height: 12,
                                      decoration: BoxDecoration(
                                        color: _statusColor(e.status),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    if (!isLast)
                                      Container(width: 2, height: 36, color: Colors.grey.shade200),
                                  ]),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(_statusLabel(e.status),
                                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                                          if (e.note != null)
                                            Text(e.note!, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                                          Text(_timeAgo(e.changedAt),
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList();
                          }(),
                        ],
                      ),
                    ),
                  ],

                  // ── Resolution Note + Images (shown when resolved) ──
                  if (post.status == ComplaintStatus.resolved &&
                      (post.resolutionNote != null || post.resolutionImages.isNotEmpty)) ...[
                    const SizedBox(height: 8),
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.check_circle_rounded,
                                  color: Colors.green.shade600, size: 16),
                            ),
                            const SizedBox(width: 8),
                            const Text('Resolution',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A237E))),
                          ]),
                          if (post.resolutionNote != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Text(post.resolutionNote!,
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.green.shade800,
                                      height: 1.5)),
                            ),
                          ],
                          if (post.resolutionImages.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text('Evidence from Committee',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade600)),
                            const SizedBox(height: 8),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: post.resolutionImages.length,
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: post.resolutionImages.length == 1 ? 1 : 2,
                                crossAxisSpacing: 6,
                                mainAxisSpacing: 6,
                                childAspectRatio: 1.2,
                              ),
                              itemBuilder: (ctx, i) => GestureDetector(
                                onTap: () => _openFullscreenImage(
                                    context, post.resolutionImages, i),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Stack(fit: StackFit.expand, children: [
                                    Image.network(
                                      _cloudinaryOptimized(post.resolutionImages[i]),
                                      fit: BoxFit.cover,
                                      gaplessPlayback: true,
                                      loadingBuilder: (ctx, child, progress) {
                                        if (progress == null) return child;
                                        return Container(
                                          color: Colors.grey.shade200,
                                          child: Center(
                                            child: CircularProgressIndicator(
                                              value: progress.expectedTotalBytes != null
                                                  ? progress.cumulativeBytesLoaded /
                                                      progress.expectedTotalBytes!
                                                  : null,
                                              strokeWidth: 2,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        );
                                      },
                                      errorBuilder: (ctx, err, stack) => Container(
                                        color: Colors.grey.shade100,
                                        child: Icon(Icons.broken_image, color: Colors.grey.shade400),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4, right: 4,
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          color: Colors.black45,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Icon(Icons.fullscreen_rounded,
                                            color: Colors.white, size: 14),
                                      ),
                                    ),
                                  ]),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  // ── Challenged Banner (visible to ALL students) ──────
                  if (post.isChallenged) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3E0),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFF9500), width: 1.5),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                color: Color(0xFFFF9500), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Resolution Challenged',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFE65100))),
                                  const SizedBox(height: 3),
                                  Text(
                                    post.challengedAt != null
                                        ? 'The reporter has challenged this resolution and escalated to the college office.'
                                        : 'The reporter has challenged this resolution.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.orange.shade800,
                                        height: 1.4),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // ── Escalation / PDF Section (owner only, resolved only) ──
                  if (post.userId == _uid &&
                      post.status == ComplaintStatus.resolved) ...[
                    const SizedBox(height: 8),
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!post.isChallenged) ...[
                            // Not yet challenged — show challenge button
                            const Text('Not Satisfied with Resolution?',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1A237E))),
                            const SizedBox(height: 4),
                            Text(
                              'Challenge the resolution to escalate this issue. '
                              'A PDF with the full complaint log will be generated '
                              'for you to present at the college office.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  height: 1.4),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _challengeResolution(post),
                                icon: const Icon(Icons.gavel_rounded, size: 18),
                                label: const Text('Challenge Resolution'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFFF6B35),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ] else if (post.status == ComplaintStatus.resolved &&
                              post.isChallenged) ...[
                            // Already challenged — show status + re-download button
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFF3E0),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(children: [
                                const Icon(Icons.check_circle_outline_rounded,
                                    color: Color(0xFFFF9500), size: 18),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'You have challenged this resolution. Present the PDF at the college office.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFFE65100)),
                                  ),
                                ),
                              ]),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () => _downloadPdf(post),
                                icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                                label: const Text('Re-download Escalation PDF'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFFF6B35),
                                  side: const BorderSide(color: Color(0xFFFF6B35)),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  // ── Comments ───────────────────────────────────────────
                  const SizedBox(height: 8),
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Comments',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1A237E))),
                        const SizedBox(height: 12),
                        StreamBuilder<List<CommentModel>>(
                          stream: SocialService.instance
                              .commentsStream(post.id!),
                          builder: (context, snap) {
                            if (snap.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                  child: Padding(
                                padding: EdgeInsets.all(24),
                                child: CircularProgressIndicator(),
                              ));
                            }
                            final comments = snap.data ?? [];
                            if (comments.isEmpty) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 24),
                                child: Center(
                                  child: Column(
                                    children: [
                                      Icon(Icons.chat_bubble_outline_rounded,
                                          size: 36,
                                          color: Colors.grey.shade300),
                                      const SizedBox(height: 8),
                                      Text(
                                        'No comments yet\nBe the first to comment!',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: Colors.grey.shade400,
                                            fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }
                            return Column(
                              children: comments
                                  .map((c) => _CommentTile(
                                        comment: c,
                                        currentUserId: _uid,
                                        onDelete: () async {
                                          await SocialService.instance
                                              .deleteComment(
                                            complaintId: post.id!,
                                            commentId: c.id,
                                          );
                                        },
                                      ))
                                  .toList(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),

          // ── Comment input bar (hidden when resolved or rejected) ─────
          if (post.status != ComplaintStatus.resolved &&
              post.status != ComplaintStatus.rejected)
            Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, -2))
              ],
            ),
            padding: EdgeInsets.only(
              left: 12,
              right: 8,
              top: 10,
              bottom: MediaQuery.of(context).viewInsets.bottom > 0
                  ? 10
                  : MediaQuery.of(context).padding.bottom + 10,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: const Color(0xFF1A237E),
                  child: Text(
                    _userName.isNotEmpty ? _userName[0].toUpperCase() : 'S',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _commentController,
                    maxLines: 4,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submitComment(),
                    decoration: InputDecoration(
                      hintText: 'Write a comment...',
                      hintStyle: TextStyle(
                          color: Colors.grey.shade400, fontSize: 14),
                      filled: true,
                      fillColor: const Color(0xFFF0F2F5),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _isSubmittingComment
                    ? const SizedBox(
                        width: 36,
                        height: 36,
                        child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : IconButton(
                        onPressed: _submitComment,
                        icon: const Icon(Icons.send_rounded),
                        color: const Color(0xFF1A237E),
                        iconSize: 22,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Comment Tile ─────────────────────────────────────────────────────────────

class _CommentTile extends StatelessWidget {
  final CommentModel comment;
  final String currentUserId;
  final VoidCallback onDelete;
  const _CommentTile(
      {required this.comment,
      required this.currentUserId,
      required this.onDelete});

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = comment.userId == currentUserId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFF1A237E).withValues(alpha: 0.1),
            child: Text(
              comment.userName.isNotEmpty
                  ? comment.userName[0].toUpperCase()
                  : 'S',
              style: const TextStyle(
                  color: Color(0xFF1A237E),
                  fontSize: 13,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F2F5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(comment.userName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(comment.text,
                          style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(_timeAgo(comment.createdAt),
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade400)),
                    if (isOwner) ...[
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: onDelete,
                        child: Text('Delete',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.red.shade400,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Returns a Cloudinary URL with auto-optimization (smaller size, faster load)
String _cloudinaryOptimized(String url, {int width = 600}) {
  try {
    // Cloudinary URLs: .../upload/v.../...
    // Insert transformation after /upload/
    final uploadIdx = url.indexOf('/upload/');
    if (uploadIdx == -1) return url;
    final insert = '/upload/w_$width,q_auto,f_auto';
    return url.substring(0, uploadIdx) + insert + url.substring(uploadIdx + 7);
  } catch (_) {
    return url;
  }
}

// ── Fullscreen Image Viewer ────────────────────────────────────────────────
// StatefulWidget so counter updates correctly when swiping between images
class _FullscreenImageViewer extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;
  const _FullscreenImageViewer({required this.urls, required this.initialIndex});

  @override
  State<_FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<_FullscreenImageViewer> {
  late int _currentIndex;
  late PageController _pageCtrl;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        // Counter updates as user swipes
        title: Text('${_currentIndex + 1} / ${widget.urls.length}'),
      ),
      body: PageView.builder(
        controller: _pageCtrl,
        itemCount: widget.urls.length,
        onPageChanged: (i) => setState(() => _currentIndex = i),
        itemBuilder: (ctx, i) => InteractiveViewer(
          child: Center(
            child: Image.network(
              widget.urls[i],
              fit: BoxFit.contain,
              gaplessPlayback: true,
              loadingBuilder: (ctx, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white54, strokeWidth: 2),
                );
              },
              errorBuilder: (c, e, s) =>
                  const Icon(Icons.broken_image, color: Colors.white54, size: 64),
            ),
          ),
        ),
      ),
    );
  }
}
