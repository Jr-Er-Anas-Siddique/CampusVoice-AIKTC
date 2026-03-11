// lib/features/feed/presentation/pages/feed_page.dart
//
// Social media style feed showing all campus complaints.
// Design consistent with login/signup — primary 0xFF1A237E.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';
import '../../../../models/post_model.dart';
import '../../../../services/auth_service.dart';
import '../../../posts/presentation/pages/report_issue_page.dart';

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
        // Client-side: show posts where isPublic is true OR field is absent (old posts)
        .where((post) => post.isPublic)
        .toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.campaign_rounded, size: 22),
            SizedBox(width: 8),
            Text(
              'CampusVoice',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            tooltip: 'Sign out',
            onPressed: () async {
              await AuthService.instance.signOut();
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _CategoryFilterBar(
            selected: _filterCategory,
            onSelected: (cat) =>
                setState(() => _filterCategory = cat),
          ),
        ),
      ),
      body: StreamBuilder<List<PostModel>>(
        stream: _feedStream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF1A237E)),
            );
          }

          if (snap.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline,
                      color: Colors.red.shade400, size: 48),
                  const SizedBox(height: 12),
                  Text('Failed to load complaints',
                      style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            );
          }

          final posts = snap.data ?? [];

          if (posts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inbox_outlined,
                      size: 64, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  Text(
                    _filterCategory == null
                        ? 'No complaints yet.'
                        : 'No ${_filterCategory!.label} complaints.',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Be the first to report an issue.',
                    style: TextStyle(
                        color: Colors.grey.shade400, fontSize: 13),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            color: const Color(0xFF1A237E),
            onRefresh: () async =>
                setState(() {}), // triggers stream rebuild
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: posts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (ctx, i) => ComplaintCard(post: posts[i]),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => const ReportIssuePage()),
        ),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Report Issue',
            style: TextStyle(fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ── Category Filter Bar ───────────────────────────────────────────────────────

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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // "All" chip
          _FilterChip(
            label: 'All',
            emoji: '📋',
            isSelected: selected == null,
            onTap: () => onSelected(null),
          ),
          const SizedBox(width: 8),
          ...ComplaintCategory.values.map((cat) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _FilterChip(
                  label: cat.label,
                  emoji: cat.icon,
                  isSelected: selected == cat,
                  onTap: () =>
                      onSelected(selected == cat ? null : cat),
                ),
              )),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String emoji;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.emoji,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? Colors.white
                : Colors.white.withOpacity(0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? const Color(0xFF1A237E)
                    : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Complaint Card ────────────────────────────────────────────────────────────

class ComplaintCard extends StatelessWidget {
  final PostModel post;
  const ComplaintCard({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.indigo.withOpacity(0.07),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1A237E), Color(0xFF3949AB)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      post.userName.isNotEmpty
                          ? post.userName[0].toUpperCase()
                          : 'S',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.userName.isNotEmpty
                            ? post.userName
                            : 'Student',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF1A237E),
                        ),
                      ),
                      Text(
                        _formatTime(post.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
                // Category badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _categoryColor(post.category).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color:
                          _categoryColor(post.category).withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(post.category.icon,
                          style: const TextStyle(fontSize: 11)),
                      const SizedBox(width: 4),
                      Text(
                        post.category.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _categoryColor(post.category),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Title & Description ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  post.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A237E),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  post.description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),

          // ── Location chip ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Icon(Icons.location_on_outlined,
                    size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _locationText(post),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (post.isOnCampus == true)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.gps_fixed_rounded,
                            size: 10, color: Colors.green.shade600),
                        const SizedBox(width: 3),
                        Text('GPS verified',
                            style: TextStyle(
                                fontSize: 10,
                                color: Colors.green.shade600,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ── Unified Media Carousel (images + videos in sequence) ──
          if (post.imageUrls.isNotEmpty || post.videoPaths.isNotEmpty) ...[
            const SizedBox(height: 12),
            _MediaCarousel(
              imageUrls: post.imageUrls,
              videoPaths: post.videoPaths,
            ),
          ],

          // ── Footer ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Row(
              children: [
                _StatusBadge(status: post.status),
                const Spacer(),
                if (post.imageUrls.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.photo_outlined,
                          size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 3),
                      Text('${post.imageUrls.length}',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade400)),
                      const SizedBox(width: 10),
                    ],
                  ),
                if (post.videoPaths.isNotEmpty)
                  Row(
                    children: [
                      Icon(Icons.videocam_outlined,
                          size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 3),
                      Text('${post.videoPaths.length}',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade400)),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _locationText(PostModel post) {
    final parts = [post.building];
    if (post.floor != null) parts.add(post.floor!);
    if (post.roomNumber != null) parts.add(post.roomNumber!);
    return parts.join(' • ');
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  Color _categoryColor(ComplaintCategory cat) {
    switch (cat) {
      case ComplaintCategory.infrastructure:
        return const Color(0xFFE65100);
      case ComplaintCategory.academic:
        return const Color(0xFF1565C0);
      case ComplaintCategory.administrative:
        return const Color(0xFF6A1B9A);
      case ComplaintCategory.safety:
        return const Color(0xFFC62828);
      case ComplaintCategory.other:
        return const Color(0xFF2E7D32);
    }
  }
}

// ── Unified Media Carousel (images + videos in one PageView) ─────────────────

// Each item is either an image URL or a video path — we wrap them in a sealed type
class _MediaItem {
  final String url;
  final bool isVideo;
  const _MediaItem({required this.url, required this.isVideo});
}

class _MediaCarousel extends StatefulWidget {
  final List<String> imageUrls;
  final List<String> videoPaths;
  const _MediaCarousel({required this.imageUrls, required this.videoPaths});

  @override
  State<_MediaCarousel> createState() => _MediaCarouselState();
}

class _MediaCarouselState extends State<_MediaCarousel> {
  int _current = 0;
  late final PageController _pageController;
  late final List<_MediaItem> _items;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    // Images first, then videos — in order
    _items = [
      ...widget.imageUrls.map((u) => _MediaItem(url: u, isVideo: false)),
      ...widget.videoPaths.map((v) => _MediaItem(url: v, isVideo: true)),
    ];
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PageView.builder(
            controller: _pageController,
            itemCount: _items.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (ctx, i) {
              final item = _items[i];
              if (item.isVideo) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _LazyVideoPlayer(videoUrl: item.url),
                );
              } else {
                return GestureDetector(
                  onTap: () => _showFullScreen(context, item.url),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox.expand(
                        child: _buildImage(item.url),
                      ),
                    ),
                  ),
                );
              }
            },
          ),
        ),
        if (_items.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _items.length,
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

  Widget _buildImage(String url) {
    if (url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (ctx, child, progress) {
          if (progress == null) return child;
          return Container(
            color: Colors.grey.shade100,
            child: const Center(
              child: CircularProgressIndicator(
                  color: Color(0xFF1A237E), strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (_, __, ___) => Container(
          color: Colors.grey.shade100,
          child: Icon(Icons.broken_image_outlined,
              color: Colors.grey.shade400, size: 40),
        ),
      );
    } else {
      final file = File(url);
      if (file.existsSync()) {
        return Image.file(file,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity);
      }
      return Container(
        color: Colors.grey.shade100,
        child: Icon(Icons.broken_image_outlined,
            color: Colors.grey.shade400, size: 40),
      );
    }
  }

  void _showFullScreen(BuildContext context, String url) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _FullScreenImage(url: url),
    ));
  }
}

class _FullScreenImage extends StatelessWidget {
  final String url;
  const _FullScreenImage({required this.url});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          child: url.startsWith('http')
              ? Image.network(url, fit: BoxFit.contain)
              : Image.file(File(url), fit: BoxFit.contain),
        ),
      ),
    );
  }
}

// ── Lazy Video Player ─────────────────────────────────────────────────────────
// Shows first-frame thumbnail. Only fully initializes audio/playback on tap.

class _LazyVideoPlayer extends StatefulWidget {
  final String videoUrl;
  const _LazyVideoPlayer({required this.videoUrl});

  @override
  State<_LazyVideoPlayer> createState() => _LazyVideoPlayerState();
}

class _LazyVideoPlayerState extends State<_LazyVideoPlayer> {
  VideoPlayerController? _controller;
  bool _thumbnailReady = false; // first frame seeked, ready to show
  bool _playing = false;        // user has tapped play
  bool _loading = false;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  // Initialize controller, seek to frame 0 for thumbnail, then pause.
  // This is lightweight — no buffering beyond first frame.
  Future<void> _loadThumbnail() async {
    try {
      VideoPlayerController controller;
      if (widget.videoUrl.startsWith('http')) {
        controller = VideoPlayerController.networkUrl(
            Uri.parse(widget.videoUrl));
      } else {
        final file = File(widget.videoUrl);
        if (!file.existsSync()) {
          if (mounted) setState(() => _hasError = true);
          return;
        }
        controller = VideoPlayerController.file(file);
      }
      await controller.initialize();
      // Seek to start to render first frame as thumbnail
      await controller.seekTo(Duration.zero);
      if (!mounted) { controller.dispose(); return; }
      setState(() {
        _controller = controller;
        _thumbnailReady = true;
      });
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  Future<void> _togglePlay() async {
    if (_controller == null) return;
    setState(() => _loading = true);
    try {
      if (_controller!.value.isPlaying) {
        await _controller!.pause();
      } else {
        await _controller!.play();
        setState(() => _playing = true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Icon(Icons.videocam_off_outlined,
              color: Colors.grey.shade400, size: 32),
        ),
      );
    }

    if (!_thumbnailReady) {
      // Still loading thumbnail
      return Container(
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
        ),
      );
    }

    // Thumbnail ready — show video frame with play overlay
    return GestureDetector(
      onTap: _togglePlay,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Video fits within container without cropping
            FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            ),
            // Play/pause overlay — hidden when playing, shown when paused
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _controller!,
              builder: (_, value, __) {
                final showOverlay = !value.isPlaying;
                return AnimatedOpacity(
                  opacity: showOverlay ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    color: Colors.black26,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 36),
                      ),
                    ),
                  ),
                );
              },
            ),
            // Progress bar always at bottom
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: VideoProgressIndicator(
                _controller!,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Color(0xFF1A237E),
                  bufferedColor: Colors.white38,
                  backgroundColor: Colors.black26,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


// ── Status Badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final ComplaintStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData icon;

    switch (status) {
      case ComplaintStatus.submitted:
        color = Colors.blue;
        label = 'Submitted';
        icon = Icons.send_rounded;
        break;
      case ComplaintStatus.inProgress:
        color = Colors.orange;
        label = 'In Progress';
        icon = Icons.engineering_rounded;
        break;
      case ComplaintStatus.resolved:
        color = Colors.green;
        label = 'Resolved';
        icon = Icons.check_circle_rounded;
        break;
      case ComplaintStatus.rejected:
        color = Colors.red;
        label = 'Rejected';
        icon = Icons.cancel_rounded;
        break;
      default:
        color = Colors.grey;
        label = 'Draft';
        icon = Icons.edit_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
