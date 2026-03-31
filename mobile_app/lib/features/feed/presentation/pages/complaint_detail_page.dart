// lib/features/feed/presentation/pages/complaint_detail_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../models/post_model.dart';
import '../../../../models/comment_model.dart';
import '../../../../services/social_service.dart';
import '../../../../services/auth_service.dart';
import 'feed_page.dart' show FeedMediaCarousel;

class ComplaintDetailPage extends StatefulWidget {
  final PostModel post;
  const ComplaintDetailPage({super.key, required this.post});

  @override
  State<ComplaintDetailPage> createState() => _ComplaintDetailPageState();
}

class _ComplaintDetailPageState extends State<ComplaintDetailPage> {
  final _commentController = TextEditingController();
  bool _isSubmittingComment = false;

  String get _uid => AuthService.instance.currentUser?.uid ?? '';
  String get _userName =>
      AuthService.instance.currentUser?.displayName ?? 'Student';

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
                          ...post.statusHistory.asMap().entries.map((entry) {
                            final i = entry.key;
                            final e = entry.value;
                            final isLast =
                                i == post.statusHistory.length - 1;
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Column(
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: _statusColor(e.status),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    if (!isLast)
                                      Container(
                                          width: 2,
                                          height: 36,
                                          color: Colors.grey.shade200),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(
                                        bottom: isLast ? 0 : 12),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(_statusLabel(e.status),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14)),
                                        if (e.note != null)
                                          Text(e.note!,
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  color:
                                                      Colors.grey.shade600)),
                                        Text(_timeAgo(e.changedAt),
                                            style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    Colors.grey.shade400)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }),
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

          // ── Comment input bar ──────────────────────────────────────────
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
