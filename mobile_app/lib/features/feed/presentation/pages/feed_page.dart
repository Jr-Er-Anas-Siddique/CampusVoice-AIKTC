// lib/features/feed/presentation/pages/feed_page.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';
import '../../../../models/post_model.dart';
import '../../../../services/auth_service.dart';
import '../../../../services/social_service.dart';
import '../../../posts/presentation/pages/report_issue_page.dart';
import 'complaint_detail_page.dart';
import 'my_complaints_page.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});
  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  ComplaintCategory? _filterCategory;

  Stream<List<PostModel>> get _feedStream {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('complaints')
        .where('status', isEqualTo: 'submitted')
        .orderBy('createdAt', descending: true);
    if (_filterCategory != null) {
      query = query.where('category', isEqualTo: _filterCategory!.name);
    }
    return query.snapshots().map((snap) => snap.docs
        .map((doc) => PostModel.fromFirestore(doc.data(), doc.id))
        .where((p) => p.isPublic)
        .toList());
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A237E),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.campaign_rounded, color: Colors.white, size: 26),
            const SizedBox(width: 8),
            const Text('CampusVoice',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.assignment_outlined, color: Colors.white),
            tooltip: 'My Complaints',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const MyComplaintsPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            onPressed: () => AuthService.instance.signOut(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _CategoryFilterBar(
            selected: _filterCategory,
            onSelected: (cat) => setState(() => _filterCategory = cat),
          ),
        ),
      ),
      body: StreamBuilder<List<PostModel>>(
        stream: _feedStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Color(0xFF1A237E)));
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final posts = snap.data ?? [];
          if (posts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined,
                      size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('No complaints yet',
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 16)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: posts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) => ComplaintCard(post: posts[i]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Report Issue',
            style: TextStyle(fontWeight: FontWeight.w600)),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ReportIssuePage()),
        ),
      ),
    );
  }
}

// ── Category Filter Bar ──────────────────────────────────────────────────────

class _CategoryFilterBar extends StatelessWidget {
  final ComplaintCategory? selected;
  final ValueChanged<ComplaintCategory?> onSelected;
  const _CategoryFilterBar(
      {required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _Chip(
            label: 'All',
            emoji: '📋',
            isSelected: selected == null,
            onTap: () => onSelected(null),
          ),
          ...ComplaintCategory.values.map((cat) => _Chip(
                label: cat.label,
                emoji: cat.icon,
                isSelected: selected == cat,
                onTap: () => onSelected(selected == cat ? null : cat),
              )),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label, emoji;
  final bool isSelected;
  final VoidCallback onTap;
  const _Chip(
      {required this.label,
      required this.emoji,
      required this.isSelected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isSelected
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? const Color(0xFF1A237E)
                        : Colors.white)),
          ],
        ),
      ),
    );
  }
}

// ── Complaint Card ───────────────────────────────────────────────────────────

class ComplaintCard extends StatelessWidget {
  final PostModel post;
  const ComplaintCard({super.key, required this.post});

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Color _statusColor(ComplaintStatus s) {
    switch (s) {
      case ComplaintStatus.submitted: return Colors.orange;
      case ComplaintStatus.inProgress: return Colors.blue;
      case ComplaintStatus.resolved: return Colors.green;
      case ComplaintStatus.rejected: return Colors.red;
      default: return Colors.grey;
    }
  }

  String _statusLabel(ComplaintStatus s) {
    switch (s) {
      case ComplaintStatus.submitted: return 'Pending';
      case ComplaintStatus.inProgress: return 'In Progress';
      case ComplaintStatus.resolved: return 'Resolved';
      case ComplaintStatus.rejected: return 'Rejected';
      default: return 'Draft';
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = AuthService.instance.currentUser?.uid ?? '';

    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ComplaintDetailPage(post: post))),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF1A237E),
                    child: Text(
                      post.userName.isNotEmpty
                          ? post.userName[0].toUpperCase()
                          : 'S',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(post.userName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14)),
                        Text(
                          '${post.building}  •  ${_timeAgo(post.createdAt)}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  // Status badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _statusColor(post.status)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _statusLabel(post.status),
                      style: TextStyle(
                          color: _statusColor(post.status),
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),

            // ── Category tag + title ─────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
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
                  const SizedBox(height: 4),
                  Text(post.title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1A237E))),
                  const SizedBox(height: 4),
                  Text(post.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          height: 1.4)),
                ],
              ),
            ),

            // ── Media ────────────────────────────────────────────
            if (post.imageUrls.isNotEmpty || post.videoPaths.isNotEmpty) ...[
              const SizedBox(height: 10),
              FeedMediaCarousel(
                  imageUrls: post.imageUrls, videoPaths: post.videoPaths),
            ],

            // ── Action bar ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Row(
                children: [
                  // Support button — live
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('complaints')
                        .doc(post.id)
                        .collection('supporters')
                        .doc(uid)
                        .snapshots(),
                    builder: (context, snap) {
                      final supported = snap.data?.exists ?? false;
                      return GestureDetector(
                        onTap: () => SocialService.instance.toggleSupport(
                            complaintId: post.id!, userId: uid),
                        child: Row(
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: Icon(
                                supported
                                    ? Icons.thumb_up_rounded
                                    : Icons.thumb_up_alt_outlined,
                                key: ValueKey(supported),
                                size: 20,
                                color: supported
                                    ? const Color(0xFF1A237E)
                                    : Colors.grey.shade500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            // Live support count
                            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                              stream: FirebaseFirestore.instance
                                  .collection('complaints')
                                  .doc(post.id)
                                  .snapshots(),
                              builder: (context, countSnap) {
                                final count = countSnap.hasData
                                    ? ((countSnap.data!.data()?[
                                            'supportCount'] ??
                                        post.supportCount) as int)
                                    : post.supportCount;
                                return Text('$count',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: supported
                                            ? const Color(0xFF1A237E)
                                            : Colors.grey.shade500));
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(width: 20),

                  // Comment count
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('complaints')
                        .doc(post.id)
                        .snapshots(),
                    builder: (context, snap) {
                      final count = snap.hasData
                          ? ((snap.data!.data()?['commentCount'] ??
                              post.commentCount) as int)
                          : post.commentCount;
                      return Row(
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded,
                              size: 19, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text('$count',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade500)),
                        ],
                      );
                    },
                  ),

                  const Spacer(),

                  // GPS verified
                  if (post.isOnCampus == true)
                    Row(
                      children: [
                        Icon(Icons.verified_rounded,
                            size: 14, color: Colors.green.shade500),
                        const SizedBox(width: 3),
                        Text('Verified',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.green.shade600,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Media Item Model ─────────────────────────────────────────────────────────

enum _MediaType { image, video }

class _MediaItem {
  final String url;
  final _MediaType type;
  const _MediaItem({required this.url, required this.type});
}

// ── Feed Media Carousel ──────────────────────────────────────────────────────

class FeedMediaCarousel extends StatefulWidget {
  final List<String> imageUrls;
  final List<String> videoPaths;
  const FeedMediaCarousel(
      {super.key, required this.imageUrls, required this.videoPaths});

  @override
  State<FeedMediaCarousel> createState() => _FeedMediaCarouselState();
}

class _FeedMediaCarouselState extends State<FeedMediaCarousel> {
  int _current = 0;

  List<_MediaItem> get _items => [
        ...widget.imageUrls
            .map((u) => _MediaItem(url: u, type: _MediaType.image)),
        ...widget.videoPaths
            .map((p) => _MediaItem(url: p, type: _MediaType.video)),
      ];

  void _openFullscreen(int index) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FullScreenMediaViewer(
        items: _items,
        initialIndex: index,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PageView.builder(
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) {
              final item = items[i];
              return item.type == _MediaType.image
                  ? _CarouselImage(
                      url: item.url,
                      onTap: () => _openFullscreen(i),
                    )
                  : _CarouselVideo(
                      path: item.url,
                      onTapFullscreen: () => _openFullscreen(i),
                    );
            },
          ),
        ),
        if (items.length > 1) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              items.length,
              (i) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: _current == i ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _current == i
                      ? const Color(0xFF1A237E)
                      : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Carousel Image Tile ──────────────────────────────────────────────────────

class _CarouselImage extends StatelessWidget {
  final String url;
  final VoidCallback onTap;
  const _CarouselImage({required this.url, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (_, child, progress) => progress == null
                ? child
                : Container(
                    color: Colors.grey.shade100,
                    child: const Center(child: CircularProgressIndicator())),
            errorBuilder: (_, __, ___) => Container(
                color: Colors.grey.shade100,
                child:
                    const Icon(Icons.broken_image, size: 48, color: Colors.grey)),
          ),
          // Camera icon badge top-right
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.photo_rounded,
                  color: Colors.white, size: 14),
            ),
          ),
          // Tap to expand hint
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.zoom_out_map_rounded,
                  color: Colors.white, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Carousel Video Tile ──────────────────────────────────────────────────────

class _CarouselVideo extends StatefulWidget {
  final String path;
  final VoidCallback onTapFullscreen;
  const _CarouselVideo(
      {required this.path, required this.onTapFullscreen});

  @override
  State<_CarouselVideo> createState() => _CarouselVideoState();
}

class _CarouselVideoState extends State<_CarouselVideo> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ctrl = widget.path.startsWith('http')
        ? VideoPlayerController.networkUrl(Uri.parse(widget.path))
        : VideoPlayerController.file(File(widget.path));
    _controller = ctrl;
    await ctrl.initialize();
    await ctrl.seekTo(Duration.zero);
    if (mounted) setState(() => _initialized = true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: !_initialized
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white))
          : Stack(
              fit: StackFit.expand,
              children: [
                // Video
                FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: _controller!.value.size.width,
                    height: _controller!.value.size.height,
                    child: VideoPlayer(_controller!),
                  ),
                ),

                // Play/pause overlay
                ValueListenableBuilder(
                  valueListenable: _controller!,
                  builder: (_, v, __) => GestureDetector(
                    onTap: () {
                      setState(() {
                        _playing = !v.isPlaying;
                        v.isPlaying
                            ? _controller!.pause()
                            : _controller!.play();
                      });
                    },
                    child: AnimatedOpacity(
                      opacity: v.isPlaying ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        color: Colors.transparent,
                        child: Center(
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow_rounded,
                                color: Colors.white, size: 30),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Video duration badge top-right
                if (_initialized)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_rounded,
                              color: Colors.white, size: 12),
                          const SizedBox(width: 3),
                          Text(
                            _formatDuration(
                                _controller!.value.duration),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Fullscreen button bottom-right
                Positioned(
                  bottom: 28,
                  right: 8,
                  child: GestureDetector(
                    onTap: () {
                      _controller?.pause();
                      widget.onTapFullscreen();
                    },
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.fullscreen_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ),

                // Progress bar
                Positioned(
                  bottom: 6,
                  left: 8,
                  right: 8,
                  child: VideoProgressIndicator(
                    _controller!,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                        playedColor: Color(0xFF1A237E),
                        bufferedColor: Colors.white38,
                        backgroundColor: Colors.white12),
                  ),
                ),
              ],
            ),
    );
  }
}

// ── Full Screen Media Viewer ─────────────────────────────────────────────────
// Unified viewer for images AND videos with swipe between all media

class FullScreenMediaViewer extends StatefulWidget {
  final List<_MediaItem> items;
  final int initialIndex;
  const FullScreenMediaViewer(
      {super.key, required this.items, required this.initialIndex});

  @override
  State<FullScreenMediaViewer> createState() => _FullScreenMediaViewerState();
}

class _FullScreenMediaViewerState extends State<FullScreenMediaViewer> {
  late PageController _pageController;
  late int _current;
  bool _showUI = true;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => setState(() => _showUI = !_showUI),
        child: Stack(
          children: [
            // Media pages
            PageView.builder(
              controller: _pageController,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _current = i),
              itemBuilder: (_, i) {
                final item = widget.items[i];
                return item.type == _MediaType.image
                    ? _FullscreenImage(url: item.url)
                    : _FullscreenVideo(path: item.url);
              },
            ),

            // Top bar — close + counter
            AnimatedOpacity(
              opacity: _showUI ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      // Close button
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 28),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      const Spacer(),
                      // Counter
                      if (widget.items.length > 1)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_current + 1} / ${widget.items.length}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ),
            ),

            // Bottom dot indicators
            if (widget.items.length > 1)
              AnimatedOpacity(
                opacity: _showUI ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      widget.items.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: _current == i ? 20 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _current == i
                              ? Colors.white
                              : Colors.white38,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // Media type indicator bottom-left
            AnimatedOpacity(
              opacity: _showUI ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Positioned(
                bottom: 24,
                left: 16,
                child: Icon(
                  widget.items[_current].type == _MediaType.image
                      ? Icons.photo_rounded
                      : Icons.videocam_rounded,
                  color: Colors.white54,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Fullscreen Image ─────────────────────────────────────────────────────────

class _FullscreenImage extends StatelessWidget {
  final String url;
  const _FullscreenImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 5.0,
      child: Center(
        child: Image.network(
          url,
          fit: BoxFit.contain,
          loadingBuilder: (_, child, progress) => progress == null
              ? child
              : const Center(
                  child: CircularProgressIndicator(color: Colors.white)),
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image,
              size: 64, color: Colors.white54),
        ),
      ),
    );
  }
}

// ── Fullscreen Video ─────────────────────────────────────────────────────────

class _FullscreenVideo extends StatefulWidget {
  final String path;
  const _FullscreenVideo({required this.path});

  @override
  State<_FullscreenVideo> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<_FullscreenVideo> {
  VideoPlayerController? _controller;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final ctrl = widget.path.startsWith('http')
        ? VideoPlayerController.networkUrl(Uri.parse(widget.path))
        : VideoPlayerController.file(File(widget.path));
    _controller = ctrl;
    await ctrl.initialize();
    await ctrl.play(); // auto-play in fullscreen
    if (mounted) setState(() => _initialized = true);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.white));
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        // Video fills screen
        Center(
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
        ),

        // Play/pause on tap
        ValueListenableBuilder(
          valueListenable: _controller!,
          builder: (_, v, __) => GestureDetector(
            onTap: () => setState(() =>
                v.isPlaying ? _controller!.pause() : _controller!.play()),
            child: AnimatedOpacity(
              opacity: v.isPlaying ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 44),
              ),
            ),
          ),
        ),

        // Bottom controls
        Positioned(
          bottom: 48,
          left: 16,
          right: 16,
          child: Column(
            children: [
              // Progress bar
              VideoProgressIndicator(
                _controller!,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.white38,
                    backgroundColor: Colors.white24),
              ),
              const SizedBox(height: 6),
              // Duration display
              ValueListenableBuilder(
                valueListenable: _controller!,
                builder: (_, v, __) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(v.position),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                    Text(
                      _formatDuration(v.duration),
                      style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

