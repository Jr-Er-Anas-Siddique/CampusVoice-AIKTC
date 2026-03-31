// lib/services/moderation_service.dart
//
// Client-side System Moderator — runs at submit time.
// No Cloud Functions or Blaze plan needed.
//
// Checks (in order):
//   1. Content quality    — title/description minimum standards
//   2. Spam detection     — same user posting too frequently
//   3. Harassment/threats — threatening language detection
//   4. Abusive language   — profanity + regional abuse words
//   5. Personal attacks   — targeting specific people
//   6. Irrelevant content — test/nonsense posts
//   7. Sensitive content  — ragging/harassment should be private
//   8. GPS validation     — infrastructure must be on campus
//
// Decision:
//   APPROVED → status = approved  → visible in public feed
//   FLAGGED  → status = flagged   → hidden, rejection reason stored
//
// Rejection reasons shown to student in My Complaints tab.

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/post_model.dart';

// ── Rejection Category ────────────────────────────────────────────────────────

enum RejectionCategory {
  falseComplaint,
  spam,
  abusiveLanguage,
  personalAttack,
  harassment,
  sensitiveContent,
  irrelevantIssue,
  contentQuality,
  gpsRequired,
  outsideCampus,
  rateLimitHour,
  rateLimitDay,
}

extension RejectionCategoryExt on RejectionCategory {
  String get label {
    switch (this) {
      case RejectionCategory.falseComplaint:   return 'False Complaint';
      case RejectionCategory.spam:             return 'Spam';
      case RejectionCategory.abusiveLanguage:  return 'Abusive Language';
      case RejectionCategory.personalAttack:   return 'Personal Attack';
      case RejectionCategory.harassment:       return 'Harassment';
      case RejectionCategory.sensitiveContent: return 'Sensitive Content';
      case RejectionCategory.irrelevantIssue:  return 'Irrelevant Issue';
      case RejectionCategory.contentQuality:   return 'Content Quality';
      case RejectionCategory.gpsRequired:      return 'GPS Required';
      case RejectionCategory.outsideCampus:    return 'Outside Campus';
      case RejectionCategory.rateLimitHour:    return 'Too Many Posts';
      case RejectionCategory.rateLimitDay:     return 'Daily Limit Reached';
    }
  }

  String get studentMessage {
    switch (this) {
      case RejectionCategory.falseComplaint:
        return 'Your complaint appears to be false or fabricated. Please only report genuine campus issues.';
      case RejectionCategory.spam:
        return 'This looks like a spam post. Please submit only genuine complaints.';
      case RejectionCategory.abusiveLanguage:
        return 'Your complaint contains abusive or offensive language. Please rewrite it professionally.';
      case RejectionCategory.personalAttack:
        return 'Your complaint contains personal attacks targeting individuals. Complaints must address issues, not people.';
      case RejectionCategory.harassment:
        return 'Your complaint contains threatening or harassing content. This has been flagged.';
      case RejectionCategory.sensitiveContent:
        return 'Sensitive matters like ragging or harassment should be submitted as Private. Please resubmit with visibility set to Private.';
      case RejectionCategory.irrelevantIssue:
        return 'Your complaint does not appear to be a valid campus issue. Please report only genuine problems.';
      case RejectionCategory.contentQuality:
        return 'Please provide a clear title (min 10 characters) and a proper description (min 20 characters) without ALL CAPS or repetitive characters.';
      case RejectionCategory.gpsRequired:
        return 'Infrastructure complaints require GPS verification. Please capture your location before submitting.';
      case RejectionCategory.outsideCampus:
        return 'Your GPS location is outside the AIKTC campus boundary. Infrastructure complaints must be filed from campus.';
      case RejectionCategory.rateLimitHour:
        return 'You are submitting too many complaints. Please wait at least 1 hour before submitting again.';
      case RejectionCategory.rateLimitDay:
        return 'You have reached the daily complaint limit (8 per day). Please try again tomorrow.';
    }
  }
}

// ── Moderation Result ─────────────────────────────────────────────────────────

class ModerationResult {
  final bool approved;
  final bool autoPrivate; // true = approved but forced to private
  final RejectionCategory? category;
  final String? reason;

  const ModerationResult.approved()
      : approved = true,
        autoPrivate = false,
        category = null,
        reason = null;

  /// Approved but forced private due to sensitive content.
  const ModerationResult.approvedAsPrivate()
      : approved = true,
        autoPrivate = true,
        category = null,
        reason = 'Due to the sensitive nature of your complaint, it has been automatically submitted as Private. Only the relevant committee can see it.';

  ModerationResult.flagged(this.category)
      : approved = false,
        autoPrivate = false,
        reason = category?.studentMessage;
}

// ── Moderation Service ────────────────────────────────────────────────────────

class ModerationService {
  ModerationService._();
  static final ModerationService instance = ModerationService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── Thresholds ────────────────────────────────────────────────────────────
  static const int _maxPostsPerHour = 3;
  static const int _maxPostsPerDay  = 8;

  // ── Abusive / profanity words ─────────────────────────────────────────────

  // Tier 1: Safe to use contains() — very unlikely to appear in legitimate text
  static const List<String> _abusiveContains = [
    // English — no false positive risk
    'fuck', 'shit', 'bitch', 'bastard', 'asshole', 'cunt',
    'whore', 'slut', 'porn', 'nude', 'naked', 'idiot',
    'stupid', 'moron', 'retard', 'dumbass',
    // Hindi/Marathi — all use contains
    'pagal', 'jhahil', 'jahil', 'ullu', 'gadha', 'bewakoof',
    'nalayak', 'nikamma', 'chutiya', 'harami', 'kameena',
    'kamine', 'badmash', 'bakwas', 'faltu',
    'madarchod', 'behenchod', 'bhenchod', 'maderchod',
    'gaandu', 'gaand', 'bhosdi', 'bhosdike', 'lavda',
    'saala', 'saali', 'randi', 'bsdk', 'haramzada',
    'kutta', 'kutiya', 'kutti', 'suar',
    'ghanta', 'zhavto', 'chakka', 'zavlya',
  ];

  // Tier 2: Risky — use word boundary to avoid false positives
  // ass→glass/class, dick→dictionary, piss→impossible, sex→sextant
  static const List<String> _abusiveWordBoundary = [
    'ass', 'dick', 'piss', 'sex', 'crap', 'damn',
    'jerk', 'scum', 'pig', 'dumb', 'trash', 'loser',
    'bekar', 'ganda', 'mc', 'bc', 'mf',
  ];

  // ── Harassment / threat phrases ───────────────────────────────────────────
  static const List<String> _harassmentPhrases = [
    // English threats
    'kill yourself', 'kys', 'kill him', 'kill her', 'kill them',
    'go die', 'i will hurt', 'i will find you', 'i know where you live',
    'will expose you', 'blackmail', 'rape', 'will beat you',
    'i will kill', 'gonna kill', 'want to kill',
    // Hindi/Marathi threats (romanized)
    'marunga', 'maar dunga', 'maar denge', 'mar dunga',
    'dekh lunga', 'dekh lenge', 'thappad', 'marunga tujhe',
    'teri maa', 'teri behen', 'teri gaand',
    'peetunga', 'tod dunga', 'jaan se marunga',
  ];

  // ── Personal attack patterns ──────────────────────────────────────────────
  // Even 1 match is enough — these are clearly targeting a person
  static const List<String> _personalAttackPatterns = [
    'is corrupt', 'is bad', 'is stupid', 'is useless',
    'is incompetent', 'is worst', 'is terrible', 'is horrible',
    'that professor', 'that teacher', 'that sir', 'that madam',
    'he is biased', 'she is biased', 'he takes bribe', 'she takes bribe',
    'sir is', 'madam is', 'teacher is', 'professor is',
    'he is bad', 'she is bad', 'he is corrupt', 'she is corrupt',
  ];

  // ── Test / nonsense / irrelevant indicators ───────────────────────────────
  static const List<String> _irrelevantPatterns = [
    'testing', 'test post', 'hello world', 'just checking',
    'ignore this', 'asdfgh', 'qwerty', 'xyzabc',
    'temp post', 'delete this', 'sample post', 'dummy',
  ];

  // ── Sensitive topics — must be private ────────────────────────────────────
  static const List<String> _sensitivePublicWords = [
    'ragging', 'being ragged', 'bullying', 'bullied',
    'harassed', 'harassment', 'molested', 'molestation',
    'sexually assaulted', 'assault', 'threatened',
    'casteism', 'racism', 'discriminated',
  ];

  // ── Main Moderation Method ────────────────────────────────────────────────

  Future<ModerationResult> moderate(PostModel post) async {
    final checks = <ModerationResult Function()>[
      () => _checkContentQuality(post),
      () => _checkHarassment(post),
      () => _checkAbusiveLanguage(post),
      () => _checkPersonalAttack(post),
      () => _checkIrrelevant(post),
      () => _checkSensitiveVisibility(post),
      () => _checkGps(post),
    ];

    for (final check in checks) {
      final result = check();
      if (!result.approved) return result;
    }

    // Spam check is async
    final spam = await _checkSpam(post);
    if (!spam.approved) return spam;

    return const ModerationResult.approved();
  }

  // ── Check 1: Content Quality ──────────────────────────────────────────────

  ModerationResult _checkContentQuality(PostModel post) {
    final title = post.title.trim();
    final desc  = post.description.trim();

    if (title.length < 10 || title.length > 200 || desc.length < 20) {
      return ModerationResult.flagged(RejectionCategory.contentQuality);
    }

    // ALL CAPS title
    final letters = title.replaceAll(RegExp(r'[^A-Za-z]'), '');
    if (letters.length > 4 && letters.toUpperCase() == letters) {
      return ModerationResult.flagged(RejectionCategory.contentQuality);
    }

    // Repetitive characters
    if (RegExp(r'(.)\1{6,}').hasMatch(title) ||
        RegExp(r'(.)\1{6,}').hasMatch(desc)) {
      return ModerationResult.flagged(RejectionCategory.contentQuality);
    }

    // Title same as description
    if (title.toLowerCase() == desc.toLowerCase()) {
      return ModerationResult.flagged(RejectionCategory.contentQuality);
    }

    return const ModerationResult.approved();
  }

  // ── Check 2: Harassment ───────────────────────────────────────────────────

  ModerationResult _checkHarassment(PostModel post) {
    final text = '${post.title} ${post.description}'.toLowerCase();
    for (final phrase in _harassmentPhrases) {
      if (text.contains(phrase)) {
        return ModerationResult.flagged(RejectionCategory.harassment);
      }
    }
    return const ModerationResult.approved();
  }

  // ── Check 3: Abusive Language ─────────────────────────────────────────────

  ModerationResult _checkAbusiveLanguage(PostModel post) {
    final text = '${post.title} ${post.description}'.toLowerCase();

    // Tier 1: contains() — catches plurals, suffixes (idiots, fucked, pagals)
    for (final word in _abusiveContains) {
      if (text.contains(word)) {
        return ModerationResult.flagged(RejectionCategory.abusiveLanguage);
      }
    }

    // Tier 2: word boundary — avoids false positives (ass→glass, dick→dictionary)
    for (final word in _abusiveWordBoundary) {
      if (RegExp('\\b${RegExp.escape(word)}').hasMatch(text)) {
        return ModerationResult.flagged(RejectionCategory.abusiveLanguage);
      }
    }

    return const ModerationResult.approved();
  }

  // ── Check 4: Personal Attacks ─────────────────────────────────────────────

  ModerationResult _checkPersonalAttack(PostModel post) {
    final text = '${post.title} ${post.description}'.toLowerCase();
    for (final pattern in _personalAttackPatterns) {
      if (text.contains(pattern)) {
        return ModerationResult.flagged(RejectionCategory.personalAttack);
      }
    }
    return const ModerationResult.approved();
  }

  // ── Check 5: Irrelevant / Test Content ───────────────────────────────────

  ModerationResult _checkIrrelevant(PostModel post) {
    final text = '${post.title} ${post.description}'.toLowerCase();
    for (final pattern in _irrelevantPatterns) {
      if (text.contains(pattern)) {
        return ModerationResult.flagged(RejectionCategory.irrelevantIssue);
      }
    }
    return const ModerationResult.approved();
  }

  // ── Check 6: Sensitive Content Visibility ────────────────────────────────
  // Instead of flagging, auto-switch to private and approve.

  ModerationResult _checkSensitiveVisibility(PostModel post) {
    if (!post.isPublic) return const ModerationResult.approved();
    final text = '${post.title} ${post.description}'.toLowerCase();
    for (final word in _sensitivePublicWords) {
      if (text.contains(word)) {
        return const ModerationResult.approvedAsPrivate();
      }
    }
    return const ModerationResult.approved();
  }

  // ── Check 7: GPS Validation ───────────────────────────────────────────────

  ModerationResult _checkGps(PostModel post) {
    if (post.category == ComplaintCategory.infrastructure) {
      if (post.gpsCoordinates == null) {
        return ModerationResult.flagged(RejectionCategory.gpsRequired);
      }
      if (post.isOnCampus != true) {
        return ModerationResult.flagged(RejectionCategory.outsideCampus);
      }
    }
    return const ModerationResult.approved();
  }

  // ── Check 8: Spam (async) ────────────────────────────────────────────────

  Future<ModerationResult> _checkSpam(PostModel post) async {
    try {
      final now     = DateTime.now();
      final hourAgo = now.subtract(const Duration(hours: 1));
      final dayAgo  = now.subtract(const Duration(days: 1));

      final hourSnap = await _db
          .collection('complaints')
          .where('userId', isEqualTo: post.userId)
          .where('createdAt', isGreaterThanOrEqualTo: hourAgo.toIso8601String())
          .get();
      if (hourSnap.docs.length >= _maxPostsPerHour) {
        return ModerationResult.flagged(RejectionCategory.rateLimitHour);
      }

      final daySnap = await _db
          .collection('complaints')
          .where('userId', isEqualTo: post.userId)
          .where('createdAt', isGreaterThanOrEqualTo: dayAgo.toIso8601String())
          .get();
      if (daySnap.docs.length >= _maxPostsPerDay) {
        return ModerationResult.flagged(RejectionCategory.rateLimitDay);
      }

      return const ModerationResult.approved();
    } catch (_) {
      return const ModerationResult.approved();
    }
  }
}
