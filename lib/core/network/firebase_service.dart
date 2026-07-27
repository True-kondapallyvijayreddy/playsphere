import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'gcp_bigquery_service.dart';

/// Firebase Firestore & GCP BigQuery Real-Time Service for PlaySphere.
/// Serves as the primary production backend data layer for app storage,
/// realtime subscriptions, and GCP BigQuery data warehousing telemetry.
class FirebaseService {
  FirebaseService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Collection References
  static CollectionReference<Map<String, dynamic>> get orgsRef => _firestore.collection('organizations');
  static CollectionReference<Map<String, dynamic>> get competitionsRef => _firestore.collection('competitions');
  static CollectionReference<Map<String, dynamic>> get fixturesRef => _firestore.collection('fixtures');
  static CollectionReference<Map<String, dynamic>> get matchEventsRef => _firestore.collection('match_events');
  static CollectionReference<Map<String, dynamic>> get registrationsRef => _firestore.collection('registrations');
  static CollectionReference<Map<String, dynamic>> get clubsRef => _firestore.collection('clubs');

  /// Seed initial demo organization data into Firebase Firestore if empty
  static Future<void> initializeFirestoreData() async {
    try {
      final snapshot = await orgsRef.get();
      if (snapshot.docs.isEmpty) {
        debugPrint('[Firebase Firestore] Seeding initial production organization data...');
        
        await orgsRef.doc('maram-homes').set({
          'id': 'maram-homes',
          'name': 'Maram Homes Sports Club',
          'code': 'MHSC',
          'tier': 'enterprise',
          'created_at': FieldValue.serverTimestamp(),
        });

        await competitionsRef.doc('comp-tt-2026').set({
          'id': 'comp-tt-2026',
          'org_id': 'maram-homes',
          'name': 'Kakatiya Premier Table Tennis Open 2026',
          'sport': 'Table Tennis',
          'entrant_type': 'Individual',
          'status': 'active',
          'created_at': FieldValue.serverTimestamp(),
        });

        await fixturesRef.doc('fix-1').set({
          'id': 'fix-1',
          'org_id': 'maram-homes',
          'competition_id': 'comp-tt-2026',
          'entrant_a_id': 'prof-p1',
          'entrant_b_id': 'prof-p2',
          'score_a': 2,
          'score_b': 1,
          'status': 'live',
          'venue': 'Court 1 - Indoor Stadium',
        });
      }
    } catch (e) {
      debugPrint('[Firebase Firestore Init] Note: $e');
    }
  }

  /// Create a new Club in Firebase Firestore
  static Future<void> createClub({
    required String clubId,
    required String name,
    required String description,
    required String district,
    required String inviteCode,
  }) async {
    final clubData = {
      'id': clubId,
      'name': name,
      'description': description,
      'district': district,
      'invite_code': inviteCode,
      'role': 'admin',
      'created_at': FieldValue.serverTimestamp(),
    };

    await clubsRef.doc(clubId).set(clubData);
    await orgsRef.doc(clubId).set(clubData);

    debugPrint('[Firebase Firestore] Created Club $clubId in Firestore');
  }

  /// Save a Live Match Event to Firebase Firestore & Stream to GCP BigQuery
  static Future<void> saveMatchEvent({
    required String fixtureId,
    required String eventType,
    required Map<String, dynamic> payload,
  }) async {
    final eventDoc = {
      'fixture_id': fixtureId,
      'event_type': eventType,
      'payload': payload,
      'created_at': FieldValue.serverTimestamp(),
    };

    // 1. Save to Firebase Firestore
    await matchEventsRef.add(eventDoc);
    debugPrint('[Firebase Firestore] Match event saved to collection "match_events"');

    // 2. Stream to GCP BigQuery Analytics Warehouse
    await GCPBigQueryService.streamMatchEventToBigQuery(
      fixtureId: fixtureId,
      eventType: eventType,
      eventData: payload,
    );
  }

  /// Real-Time Stream listener for live match events from Firebase Firestore
  static Stream<QuerySnapshot<Map<String, dynamic>>> streamMatchEvents(String fixtureId) {
    return matchEventsRef
        .where('fixture_id', isEqualTo: fixtureId)
        .orderBy('created_at', descending: true)
        .snapshots();
  }

  /// Save player registration into Firebase Firestore
  static Future<void> saveRegistration({
    required String eventId,
    required String memberId,
    required String entrantType,
    required Map<String, dynamic> registrationData,
  }) async {
    await registrationsRef.add({
      'event_id': eventId,
      'member_id': memberId,
      'entrant_type': entrantType,
      'details': registrationData,
      'status': 'confirmed',
      'created_at': FieldValue.serverTimestamp(),
    });
    debugPrint('[Firebase Firestore] Registration saved in Firestore collection "registrations"');
  }
}
