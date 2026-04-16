// lib/features/committee/presentation/pages/committee_dashboard_page.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../main.dart' show AppColors;
import '../../../../models/post_model.dart';
import '../../../../models/committee_member_model.dart';
import 'committee_complaint_detail_page.dart';

class CommitteeDashboardPage extends StatefulWidget {
  final CommitteeMember member;
  const CommitteeDashboardPage({super.key, required this.member});

  @override
  State<CommitteeDashboardPage> createState() => _CommitteeDashboardPageState();
}

class _CommitteeDashboardPageState extends State<CommitteeDashboardPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Stream<List<PostModel>> get _stream {
    return FirebaseFirestore.instance
        .collection('complaints')
        .where('assignedCommittee', isEqualTo: widget.member.committee.label)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => PostModel.fromFirestore(d.data(), d.id))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PostModel>>(
      stream: _stream,
      builder: (context, snap) {
        final all = snap.data ?? [];
        final isLoading = !snap.hasData;

        final newList      = all.where((p) => p.status == ComplaintStatus.approved).toList();
        final activeList   = all.where((p) => p.status == ComplaintStatus.underReview || p.status == ComplaintStatus.inProgress).toList();
        final resolvedList = all.where((p) => p.status == ComplaintStatus.resolved || p.status == ComplaintStatus.rejected).toList();
        final flaggedList  = all.where((p) => p.status == ComplaintStatus.flagged).toList();

        return Scaffold(
          backgroundColor: const Color(0xFFF5F6FA),
          body: Column(children: [
            // ── Header ──────────────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A237E), Color(0xFF283593)],
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(widget.member.committee.label,
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 8),
                        const Text('Committee Dashboard',
                            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text(widget.member.committee.fullName,
                            style: const TextStyle(color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                  ),
                  TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.white,
                    indicatorWeight: 3,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white54,
                    labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    tabs: [
                      _BadgeTab('New',      newList.length,      false),
                      _BadgeTab('Active',   activeList.length,   false),
                      _BadgeTab('Resolved', resolvedList.length, false),
                      _BadgeTab('Flagged',  flaggedList.length,  true),
                    ],
                  ),
                ]),
              ),
            ),
            // ── Body ────────────────────────────────────────────────────
            if (isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.accent)))
            else ...[
              _StatsRow(all: all),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _ComplaintList(complaints: newList,      emptyMsg: 'No new complaints',      member: widget.member),
                    _ComplaintList(complaints: activeList,   emptyMsg: 'No active complaints',   member: widget.member),
                    _ComplaintList(complaints: resolvedList, emptyMsg: 'No resolved complaints', member: widget.member),
                    _ComplaintList(complaints: flaggedList,  emptyMsg: 'No flagged complaints',  member: widget.member),
                  ],
                ),
              ),
            ],
          ]),
        );
      },
    );
  }
}

// ── Stats Row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final List<PostModel> all;
  const _StatsRow({required this.all});

  @override
  Widget build(BuildContext context) {
    final total      = all.length;
    final active     = all.where((p) => p.status == ComplaintStatus.underReview || p.status == ComplaintStatus.inProgress).length;
    final resolved   = all.where((p) => p.status == ComplaintStatus.resolved).length;
    final pending    = all.where((p) => p.status == ComplaintStatus.approved).length;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Row(children: [
        _StatCell(value: '$total',    label: 'Total',    color: AppColors.textDark),
        _Vdivider(),
        _StatCell(value: '$pending',  label: 'New',      color: const Color(0xFF5C6BC0)),
        _Vdivider(),
        _StatCell(value: '$active',   label: 'Active',   color: AppColors.inProgress),
        _Vdivider(),
        _StatCell(value: '$resolved', label: 'Resolved', color: AppColors.resolved),
      ]),
    );
  }
}

class _StatCell extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _StatCell({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(children: [
      Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textMid)),
    ]),
  );
}

class _Vdivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 32, color: AppColors.border);
}

// ── Badge Tab ─────────────────────────────────────────────────────────────────

class _BadgeTab extends StatelessWidget {
  final String label;
  final int count;
  final bool isAlert;
  const _BadgeTab(this.label, this.count, this.isAlert);

  @override
  Widget build(BuildContext context) => Tab(
    child: count > 0
        ? Stack(clipBehavior: Clip.none, children: [
            Text(label),
            Positioned(
              right: -8,
              top: -4,
              child: Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  color: isAlert ? Colors.red : Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ])
        : Text(label),
  );
}

// ── Complaint List ────────────────────────────────────────────────────────────

class _ComplaintList extends StatelessWidget {
  final List<PostModel> complaints;
  final String emptyMsg;
  final CommitteeMember member;
  const _ComplaintList({required this.complaints, required this.emptyMsg, required this.member});

  @override
  Widget build(BuildContext context) {
    if (complaints.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.inbox_outlined, size: 56, color: AppColors.textLight.withValues(alpha: 0.4)),
        const SizedBox(height: 12),
        Text(emptyMsg, style: const TextStyle(color: AppColors.textMid, fontSize: 15, fontWeight: FontWeight.w500)),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      itemCount: complaints.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _ComplaintCard(post: complaints[i], member: member),
      ),
    );
  }
}

// ── Complaint Card ────────────────────────────────────────────────────────────

class _ComplaintCard extends StatelessWidget {
  final PostModel post;
  final CommitteeMember member;
  const _ComplaintCard({required this.post, required this.member});

  Color _color(ComplaintStatus s) {
    switch (s) {
      case ComplaintStatus.approved:    return const Color(0xFF5C6BC0);
      case ComplaintStatus.underReview: return const Color(0xFFFF9500);
      case ComplaintStatus.inProgress:  return const Color(0xFF007AFF);
      case ComplaintStatus.resolved:    return const Color(0xFF34C759);
      case ComplaintStatus.rejected:    return const Color(0xFFFF3B30);
      case ComplaintStatus.flagged:     return const Color(0xFFFF6B35);
      default:                          return AppColors.textLight;
    }
  }

  String _label(ComplaintStatus s) {
    switch (s) {
      case ComplaintStatus.approved:    return 'New';
      case ComplaintStatus.underReview: return 'Under Review';
      case ComplaintStatus.inProgress:  return 'In Progress';
      case ComplaintStatus.resolved:    return 'Resolved';
      case ComplaintStatus.rejected:    return 'Rejected';
      case ComplaintStatus.flagged:     return 'Flagged';
      default:                          return s.name;
    }
  }

  String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1)  return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24)   return '${d.inHours}h ago';
    if (d.inDays < 7)     return '${d.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final color = _color(post.status);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (ctx) => CommitteeComplaintDetailPage(post: post, member: member),
        )),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Top status bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.07),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Row(children: [
                Container(width: 8, height: 8,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(_label(post.status),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
                if (post.isChallenged) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B35).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.gavel_rounded, size: 9, color: Color(0xFFFF6B35)),
                      const SizedBox(width: 3),
                      const Text('Challenged',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Color(0xFFFF6B35))),
                    ]),
                  ),
                ],
                const Spacer(),
                if (!post.isPublic) ...[
                  const Icon(Icons.lock_outline_rounded, size: 12, color: AppColors.textLight),
                  const SizedBox(width: 6),
                ],
                Text(_ago(post.updatedAt),
                    style: const TextStyle(fontSize: 11, color: AppColors.textLight)),
              ]),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(post.category.icon, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Text(post.category.label,
                      style: const TextStyle(fontSize: 12, color: AppColors.accent, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: 5),
                Text(post.title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textDark),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(post.description,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.textMid, height: 1.4)),
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 12, color: AppColors.textLight),
                  const SizedBox(width: 3),
                  Expanded(child: Text(
                    [post.building, if (post.floor != null) post.floor!].join(', '),
                    style: const TextStyle(fontSize: 12, color: AppColors.textMid),
                    overflow: TextOverflow.ellipsis,
                  )),
                  const Icon(Icons.thumb_up_outlined, size: 12, color: AppColors.textLight),
                  const SizedBox(width: 3),
                  Text('${post.supportCount}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMid)),
                  const SizedBox(width: 8),
                  const Icon(Icons.chat_bubble_outline_rounded, size: 12, color: AppColors.textLight),
                  const SizedBox(width: 3),
                  Text('${post.commentCount}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMid)),
                  if (post.imageUrls.isNotEmpty || post.videoPaths.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.photo_outlined, size: 12, color: AppColors.textLight),
                    const SizedBox(width: 3),
                    Text('${post.imageUrls.length + post.videoPaths.length}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textMid)),
                  ],
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textLight),
                ]),
              ]),
            ),

            // Progress bar
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: LinearProgressIndicator(
                value: _progress(post.status),
                backgroundColor: AppColors.border,
                valueColor: AlwaysStoppedAnimation<Color>(color),
                minHeight: 3,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  double _progress(ComplaintStatus s) {
    switch (s) {
      case ComplaintStatus.approved:    return 0.2;
      case ComplaintStatus.underReview: return 0.5;
      case ComplaintStatus.inProgress:  return 0.75;
      case ComplaintStatus.resolved:    return 1.0;
      case ComplaintStatus.rejected:    return 1.0;
      case ComplaintStatus.flagged:     return 0.1;
      default:                          return 0.0;
    }
  }
}
