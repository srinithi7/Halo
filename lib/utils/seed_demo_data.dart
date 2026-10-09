import 'package:cloud_firestore/cloud_firestore.dart';

/// One-time demo/classroom seed data: 20 mock user profiles across 3
/// communities, with recognitions distributed so each community's Unsung
/// Hero ranking (lib/utils/unsung_hero.dart) produces a clear, explainable
/// result — someone recognized by many different people, in contrast to
/// someone else who racked up glows from one loud moment instead.
///
/// Mock users are plain `users/{uid}` documents with synthetic uids
/// (`mock_xx`) — they don't need real Firebase Auth accounts, since
/// nothing in the read path re-validates a recognition's senderId/
/// recipientId against Auth; they're just uid-shaped strings.
///
/// Writing recognitions with a senderId other than the caller's own uid
/// is normally blocked by firestore.rules (`senderId == request.auth.uid`)
/// — this only works while that rule is temporarily relaxed for seeding.
/// See firestore.rules' history/README note left alongside the relaxed
/// version for the revert step.
Future<void> seedDemoData() async {
  final firestore = FirebaseFirestore.instance;

  // Idempotency guard — re-tapping "Seed demo data" shouldn't pile up
  // duplicate recognitions on top of an already-seeded project.
  final marker =
      await firestore.collection('communities').doc('demo-design-team').get();
  if (marker.exists) return;

  const mockUsers = <String, Map<String, String>>{
    'mock_01': {'name': 'Aditi Sharma', 'phoneNumber': '+919800000001'},
    'mock_02': {'name': 'Rohan Verma', 'phoneNumber': '+919800000002'},
    'mock_03': {'name': 'Priya Nair', 'phoneNumber': '+919800000003'},
    'mock_04': {'name': 'Karan Mehta', 'phoneNumber': '+919800000004'},
    'mock_05': {'name': 'Sneha Iyer', 'phoneNumber': '+919800000005'},
    'mock_06': {'name': 'Arjun Rao', 'phoneNumber': '+919800000006'},
    'mock_07': {'name': 'Divya Pillai', 'phoneNumber': '+919800000007'},
    'mock_08': {'name': 'Vikram Singh', 'phoneNumber': '+919800000008'},
    'mock_09': {'name': 'Ananya Gupta', 'phoneNumber': '+919800000009'},
    'mock_10': {'name': 'Rahul Joshi', 'phoneNumber': '+919800000010'},
    'mock_11': {'name': 'Meera Krishnan', 'phoneNumber': '+919800000011'},
    'mock_12': {'name': 'Siddharth Kapoor', 'phoneNumber': '+919800000012'},
    'mock_13': {'name': 'Kavya Reddy', 'phoneNumber': '+919800000013'},
    'mock_14': {'name': 'Nikhil Bhat', 'phoneNumber': '+919800000014'},
    'mock_15': {'name': 'Pooja Desai', 'phoneNumber': '+919800000015'},
    'mock_16': {'name': 'Aryan Malhotra', 'phoneNumber': '+919800000016'},
    'mock_17': {'name': 'Tanvi Shah', 'phoneNumber': '+919800000017'},
    'mock_18': {'name': 'Varun Chawla', 'phoneNumber': '+919800000018'},
    'mock_19': {'name': 'Ishita Bose', 'phoneNumber': '+919800000019'},
    'mock_20': {'name': 'Aditya Menon', 'phoneNumber': '+919800000020'},
  };

  final usersBatch = firestore.batch();
  mockUsers.forEach((uid, data) {
    usersBatch.set(firestore.collection('users').doc(uid), data);
  });
  await usersBatch.commit();

  const designTeam = [
    'mock_01',
    'mock_02',
    'mock_03',
    'mock_04',
    'mock_05',
    'mock_06',
    'mock_07'
  ];
  const engineering = [
    'mock_08',
    'mock_09',
    'mock_10',
    'mock_11',
    'mock_12',
    'mock_13',
    'mock_14'
  ];
  const support = [
    'mock_15',
    'mock_16',
    'mock_17',
    'mock_18',
    'mock_19',
    'mock_20'
  ];

  final communitiesBatch = firestore.batch();
  communitiesBatch
      .set(firestore.collection('communities').doc('demo-design-team'), {
    'name': 'Design Team',
    'description': 'Product design & UX',
    'memberIds': designTeam,
    'createdAt':
        Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30))),
    'createdBy': designTeam.first,
  });
  communitiesBatch
      .set(firestore.collection('communities').doc('demo-engineering'), {
    'name': 'Engineering',
    'description': 'Backend, mobile, and infra',
    'memberIds': engineering,
    'createdAt':
        Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30))),
    'createdBy': engineering.first,
  });
  communitiesBatch
      .set(firestore.collection('communities').doc('demo-support'), {
    'name': 'Customer Support',
    'description': 'Frontline support crew',
    'memberIds': support,
    'createdAt':
        Timestamp.fromDate(DateTime.now().subtract(const Duration(days: 30))),
    'createdBy': support.first,
  });
  await communitiesBatch.commit();

  // Each spec: (communityId, senderUid, recipientUid, message, daysAgo,
  // glowerUids). Deliberately shaped per community so one person is
  // recognized broadly (the Unsung Hero) and another gets a single
  // heavily-glowed post instead (already visible, so not "unsung").
  final specs = <_RecognitionSpec>[
    // --- Design Team: Priya is the Unsung Hero (5 distinct senders,
    // modest glows). Divya is the loud contrast (1 post, 15 glows).
    _RecognitionSpec(
        'demo-design-team',
        'mock_01',
        'mock_03',
        'Priya caught a major accessibility issue in the checkout flow before it shipped.',
        12,
        ['mock_02', 'mock_04']),
    _RecognitionSpec(
        'demo-design-team',
        'mock_02',
        'mock_03',
        'Really thoughtful feedback on my prototype this week, made it so much clearer.',
        9,
        ['mock_01']),
    _RecognitionSpec(
        'demo-design-team',
        'mock_04',
        'mock_03',
        'Priya stayed late to help me finish the onboarding redesign before the deadline.',
        7,
        ['mock_05', 'mock_06']),
    _RecognitionSpec(
        'demo-design-team',
        'mock_05',
        'mock_03',
        'Great facilitation in today\'s design review, kept the discussion focused.',
        4, []),
    _RecognitionSpec(
        'demo-design-team',
        'mock_06',
        'mock_03',
        'Thanks for mentoring me through my first end to end feature design.',
        2,
        ['mock_07']),
    _RecognitionSpec(
        'demo-design-team',
        'mock_01',
        'mock_07',
        'Divya\'s new component library launch demo was absolutely fantastic to watch.',
        15, [
      'mock_02',
      'mock_03',
      'mock_04',
      'mock_05',
      'mock_06',
      'mock_07',
      'mock_08',
      'mock_09',
      'mock_10',
      'mock_11',
      'mock_12',
      'mock_13',
      'mock_14',
      'mock_15',
      'mock_16'
    ]),
    _RecognitionSpec(
        'demo-design-team',
        'mock_07',
        'mock_02',
        'Rohan\'s wireframes for the settings page saved us a full week of rework.',
        6,
        ['mock_03']),

    // --- Engineering: Meera is the Unsung Hero. Vikram is the loud contrast.
    _RecognitionSpec(
        'demo-engineering',
        'mock_09',
        'mock_11',
        'Meera quietly rewrote our flaky test suite and it has not failed since.',
        11,
        ['mock_10']),
    _RecognitionSpec(
        'demo-engineering',
        'mock_10',
        'mock_11',
        'Meera paired with me for three hours to track down that memory leak.',
        8,
        ['mock_08']),
    _RecognitionSpec(
        'demo-engineering',
        'mock_12',
        'mock_11',
        'Appreciate Meera reviewing every one of my pull requests so carefully this sprint.',
        5,
        ['mock_13', 'mock_14']),
    _RecognitionSpec(
        'demo-engineering',
        'mock_13',
        'mock_11',
        'Meera\'s runbook for the deploy process has saved on-call so much stress.',
        3, []),
    _RecognitionSpec(
        'demo-engineering',
        'mock_14',
        'mock_11',
        'Thank you for explaining the new caching layer so patiently to the whole team.',
        1,
        ['mock_09']),
    _RecognitionSpec(
        'demo-engineering',
        'mock_09',
        'mock_08',
        'Vikram\'s live migration to the new database had zero downtime, incredible work.',
        14, [
      'mock_10',
      'mock_11',
      'mock_12',
      'mock_13',
      'mock_14',
      'mock_15',
      'mock_16',
      'mock_17',
      'mock_18',
      'mock_19',
      'mock_20',
      'mock_01'
    ]),
    _RecognitionSpec(
        'demo-engineering',
        'mock_08',
        'mock_10',
        'Rahul\'s API documentation update made onboarding so much smoother this week.',
        10,
        ['mock_11']),

    // --- Support: Aryan is the Unsung Hero. Ishita is the loud contrast.
    _RecognitionSpec(
        'demo-support',
        'mock_15',
        'mock_16',
        'Aryan handled an incredibly frustrated customer with so much patience today.',
        10,
        ['mock_17']),
    _RecognitionSpec(
        'demo-support',
        'mock_17',
        'mock_16',
        'Aryan trained me on the new ticketing macros without ever losing patience.',
        6, []),
    _RecognitionSpec(
        'demo-support',
        'mock_18',
        'mock_16',
        'Thanks for covering my shift on such short notice this weekend, Aryan.',
        4,
        ['mock_19']),
    _RecognitionSpec(
        'demo-support',
        'mock_19',
        'mock_16',
        'Aryan\'s knowledge base articles have cut our repeat tickets noticeably.',
        2, []),
    _RecognitionSpec(
        'demo-support',
        'mock_15',
        'mock_19',
        'Ishita\'s response during the outage kept the whole queue calm and informed.',
        9, [
      'mock_16',
      'mock_17',
      'mock_18',
      'mock_20',
      'mock_01',
      'mock_02',
      'mock_03',
      'mock_04',
      'mock_05',
      'mock_06'
    ]),
    _RecognitionSpec(
        'demo-support',
        'mock_16',
        'mock_20',
        'Aditya\'s follow-up call turned an angry customer into a five-star review.',
        3,
        ['mock_15']),
  ];

  // Firestore batches cap at 500 writes; well within range here, but kept
  // as a single batch deliberately so a mid-seed failure can't leave a
  // community half-populated.
  final recognitionsBatch = firestore.batch();
  for (final spec in specs) {
    final ref = firestore.collection('recognitions').doc();
    recognitionsBatch.set(ref, {
      'senderId': spec.senderId,
      'recipientId': spec.recipientId,
      'recipientDisplayName': mockUsers[spec.recipientId]!['name'],
      'message': spec.message,
      'groupId': spec.communityId,
      'moderationStatus': 'approved',
      'isAnonymous': true,
      'senderDisplayName': null,
      'createdAt': Timestamp.fromDate(
          DateTime.now().subtract(Duration(days: spec.daysAgo))),
      'glowedBy': spec.glowerUids,
      'visibility': 'public',
      'allowedPhoneNumbers': <String>[],
    });
  }
  await recognitionsBatch.commit();
}

class _RecognitionSpec {
  const _RecognitionSpec(
    this.communityId,
    this.senderId,
    this.recipientId,
    this.message,
    this.daysAgo,
    this.glowerUids,
  );

  final String communityId;
  final String senderId;
  final String recipientId;
  final String message;
  final int daysAgo;
  final List<String> glowerUids;
}
