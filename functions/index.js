// functions/index.js
//
// Cloud Function: onRecognitionCreated
//
// Trigger: fires automatically whenever a new document is created in the
// Firestore "recognitions" collection (i.e. whenever a user submits a new
// RecognitionPost from the Flutter app).
//
// Purpose: forwards a minimal { postId, message } payload to an AWS SQS
// queue, so downstream systems (e.g. a moderation pipeline) can pick up
// new posts without polling Firestore directly.

const {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
  onDocumentWritten,
} = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const { SQSClient, SendMessageCommand } = require("@aws-sdk/client-sqs");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, GeoPoint, Timestamp } = require("firebase-admin/firestore");

// ---------------------------------------------------------------------------
// Step 1: Read configuration from environment variables — never hardcode
// AWS credentials or the queue URL in source.
//
// For local development, these can be supplied via a functions/.env file
// (Cloud Functions for Firebase v2 loads .env automatically). For deployed
// functions, prefer setting these as secrets via `firebase functions:secrets:set`
// or your CI/CD environment rather than committing them anywhere.
// ---------------------------------------------------------------------------
const AWS_REGION = process.env.AWS_REGION;
const AWS_ACCESS_KEY_ID = process.env.AWS_ACCESS_KEY_ID;
const AWS_SECRET_ACCESS_KEY = process.env.AWS_SECRET_ACCESS_KEY;
const SQS_QUEUE_URL = process.env.SQS_QUEUE_URL;

// Step 2: Build a single shared SQS client. Reused across invocations when
// the function instance is warm, instead of recreating it on every call.
const sqsClient = new SQSClient({
  region: AWS_REGION,
  credentials: {
    accessKeyId: AWS_ACCESS_KEY_ID,
    secretAccessKey: AWS_SECRET_ACCESS_KEY,
  },
});

// Step 3: Register the Firestore trigger.
// "recognitions/{postId}" fires this function once for every new document
// created under the recognitions collection, and gives us the document's
// path params (here, the postId) plus a snapshot of the new data.
exports.onRecognitionCreated = onDocumentCreated(
  "recognitions/{postId}",
  async (event) => {
    // Step 4: Guard against an empty/missing snapshot (shouldn't normally
    // happen on an onCreate trigger, but fail safely rather than throwing
    // on a null dereference).
    const snapshot = event.data;
    if (!snapshot) {
      logger.warn("onRecognitionCreated: no snapshot data on event, skipping.");
      return;
    }

    const postId = event.params.postId;
    const data = snapshot.data() || {};
    const message = data.message;

    // Step 5: Validate we actually have a message to forward. senderId is
    // intentionally NOT read or forwarded here — this function only ever
    // touches postId and message, keeping the anonymity boundary intact
    // even at the infrastructure level.
    if (!message) {
      logger.warn(
        `onRecognitionCreated: document ${postId} has no message field, skipping SQS send.`
      );
      return;
    }

    // Step 6: Confirm required AWS configuration is present before
    // attempting to send. Missing config is treated as a configuration
    // error, not a transient failure worth retrying indefinitely.
    if (!AWS_REGION || !SQS_QUEUE_URL) {
      logger.error(
        "onRecognitionCreated: missing AWS_REGION or SQS_QUEUE_URL environment variable. " +
          "Set these in functions/.env (local) or via firebase functions:secrets:set (deployed)."
      );
      return;
    }

    // Step 7: Build the JSON payload to forward downstream.
    const payload = {
      postId,
      message,
    };

    // Step 8: Send the message to SQS, with basic error handling so a
    // failed send is logged clearly instead of crashing the function
    // silently. We don't rethrow by default — see comment below.
    const command = new SendMessageCommand({
      QueueUrl: SQS_QUEUE_URL,
      MessageBody: JSON.stringify(payload),
    });

    try {
      const result = await sqsClient.send(command);
      logger.info(
        `onRecognitionCreated: sent postId ${postId} to SQS. MessageId: ${result.MessageId}`
      );
    } catch (error) {
      // Log full error details for debugging (CloudWatch-style structured
      // logging via firebase-functions/logger shows up in Cloud Logging).
      logger.error(`onRecognitionCreated: failed to send postId ${postId} to SQS.`, error);

      // NOTE: Firestore-triggered functions do not retry by default unless
      // the function is deployed with retry configuration AND throws an
      // error. Rethrowing here would cause Cloud Functions to retry this
      // invocation (subject to your retry policy), which is useful if SQS
      // failures are usually transient. Uncomment the next line if you want
      // that behavior:
      // throw error;
    }
  }
);

initializeApp();
const database = getFirestore();
const UNSEEN_HERO_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const RECOGNITION_SYNC_FIELDS = [
  "recipientId",
  "isUnseenHeroCandidate",
  "location",
  "areaName",
  "geohashPrefix",
  "locationPrecision",
  "createdAt",
  "moderationStatus",
  "groupId",
  "message",
];

function presenceReference(recognitionId) {
  return database.collection("unseenHeroLocations").doc(recognitionId);
}

function isGeoPoint(value) {
  return value instanceof GeoPoint ||
    (value &&
      typeof value.latitude === "number" &&
      typeof value.longitude === "number");
}

async function removeUnseenHeroPresence(recognitionId) {
  const reference = presenceReference(recognitionId);
  const snapshot = await reference.get();
  if (snapshot.exists) {
    await reference.delete();
  }
}

async function syncUnseenHeroPresence(recognitionId, recognition) {
  if (!recognition ||
      recognition.isUnseenHeroCandidate !== true ||
      recognition.moderationStatus !== "approved" ||
      typeof recognition.recipientId !== "string" ||
      !isGeoPoint(recognition.location) ||
      typeof recognition.areaName !== "string" ||
      typeof recognition.geohashPrefix !== "string" ||
      !(recognition.createdAt instanceof Timestamp)) {
    await removeUnseenHeroPresence(recognitionId);
    return;
  }

  const heroId = recognition.recipientId;
  const [settingsSnapshot, profileSnapshot, communitySnapshot] =
    await Promise.all([
      database
        .collection("users")
        .doc(heroId)
        .collection("unseenHeroSettings")
        .doc("settings")
        .get(),
      database.collection("users").doc(heroId).get(),
      database.collection("communities").doc(recognition.groupId).get(),
    ]);

  const settings = settingsSnapshot.data();
  if (!settings || settings.visibleOnSafeWalk !== true) {
    await removeUnseenHeroPresence(recognitionId);
    return;
  }

  const recognizedAtMillis = recognition.createdAt.toMillis();
  const now = Date.now();
  if (recognizedAtMillis > now + 5 * 60 * 1000 ||
      now - recognizedAtMillis > UNSEEN_HERO_TTL_MS) {
    await removeUnseenHeroPresence(recognitionId);
    return;
  }

  const profile = profileSnapshot.data();
  const community = communitySnapshot.data();
  await presenceReference(recognitionId).set(
    {
      heroId,
      heroName:
        typeof profile?.name === "string" && profile.name.length > 0
          ? profile.name
          : "A HALO hero",
      communityId: recognition.groupId,
      communityName:
        typeof community?.name === "string" && community.name.length > 0
          ? community.name
          : "HALO community",
      areaName: recognition.areaName,
      location: new GeoPoint(
        recognition.location.latitude,
        recognition.location.longitude
      ),
      message: recognition.message,
      recognizedAt: recognition.createdAt,
      helpAvailable: settings.acceptingHelpRequests === true,
      sharePhoneAfterAcceptance: settings.sharePhoneAfterAcceptance === true,
      visibleUntil: Timestamp.fromMillis(recognizedAtMillis + UNSEEN_HERO_TTL_MS),
      geohashPrefix: recognition.geohashPrefix,
    },
    { merge: true }
  );
}

async function syncUnseenHeroPresencesForUser(heroId) {
  const recognitions = await database
    .collection("recognitions")
    .where("recipientId", "==", heroId)
    .where("isUnseenHeroCandidate", "==", true)
    .get();
  const recognitionIds = new Set();
  for (const snapshot of recognitions.docs) {
    recognitionIds.add(snapshot.id);
    await syncUnseenHeroPresence(snapshot.id, snapshot.data());
  }

  const existing = await database
    .collection("unseenHeroLocations")
    .where("heroId", "==", heroId)
    .get();
  await Promise.all(
    existing.docs
      .filter((snapshot) => !recognitionIds.has(snapshot.id))
      .map((snapshot) => snapshot.ref.delete())
  );
}

exports.syncUnseenHeroPresenceOnRecognitionCreated = onDocumentCreated(
  "recognitions/{postId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;
    await syncUnseenHeroPresence(event.params.postId, snapshot.data());
  }
);

exports.syncUnseenHeroPresenceOnRecognitionUpdated = onDocumentUpdated(
  "recognitions/{postId}",
  async (event) => {
    const before = event.data?.before.data() || {};
    const after = event.data?.after.data() || {};
    const changed = RECOGNITION_SYNC_FIELDS.some(
      (field) => JSON.stringify(before[field]) !== JSON.stringify(after[field])
    );
    if (changed) {
      await syncUnseenHeroPresence(event.params.postId, after);
    }
  }
);

exports.removeUnseenHeroPresenceOnRecognitionDeleted = onDocumentDeleted(
  "recognitions/{postId}",
  async (event) => {
    await removeUnseenHeroPresence(event.params.postId);
  }
);

exports.syncUnseenHeroPresenceOnSettingsWritten = onDocumentWritten(
  "users/{userId}/unseenHeroSettings/settings",
  async (event) => {
    await syncUnseenHeroPresencesForUser(event.params.userId);
  }
);

// ---------------------------------------------------------------------------
// Layer 2 moderation: tally community votes on an incident report.
//
// The client may cast a vote but must never decide the outcome. This
// function owns `incidents/{incidentId}.layer2` and `moderationStatus`, and
// is the only writer of them — which is what stops anyone from marking their
// own report "confirmed", or burying a report by marking it "rejected".
//
// Threshold and margin mirror ModerationService.applyCommunityReview on the
// client so the UI can predict the outcome; the server is authoritative.
// ---------------------------------------------------------------------------

const MODERATION_REVIEW_THRESHOLD = 3;

// Map incident moderation status to the Unseen Hero enum-free shape used on
// the document. Kept as strings to avoid importing the Dart enum.
const STATUS_UNDER_REVIEW = "underReview";
const STATUS_CONFIRMED = "confirmed";
const STATUS_REJECTED = "rejected";

async function tallyIncidentModeration(incidentId) {
  const db = getFirestore();
  const incidentRef = db.collection("incidents").doc(incidentId);

  const voteSnapshot = await incidentRef
    .collection("moderationVotes")
    .get();

  let confirm = 0;
  let reject = 0;
  for (const doc of voteSnapshot.docs) {
    const verdict = doc.data().verdict;
    if (verdict === "confirm") confirm += 1;
    else if (verdict === "reject") reject += 1;
  }

  const total = confirm + reject;
  let nextStatus = null;
  if (total >= MODERATION_REVIEW_THRESHOLD) {
    // Strict majority; a tie leaves the report exactly where it was rather
    // than defaulting to whichever answer is cheaper to compute.
    if (confirm > reject) nextStatus = STATUS_CONFIRMED;
    else if (reject > confirm) nextStatus = STATUS_REJECTED;
  } else {
    nextStatus = STATUS_UNDER_REVIEW;
  }

  await incidentRef.update({
    layer2: {
      verdict: nextStatus === STATUS_CONFIRMED
        ? "confirmed"
        : nextStatus === STATUS_REJECTED
          ? "rejected"
          : "pending",
      votes: total,
      confirm,
      reject,
    },
    moderationStatus: nextStatus,
  });

  return { nextStatus, confirm, reject, total };
}

exports.tallyIncidentModerationOnVote = onDocumentCreated(
  "incidents/{incidentId}/moderationVotes/{voterId}",
  async (event) => {
    const result = await tallyIncidentModeration(event.params.incidentId);
    logger.info("Incident moderation tallied", {
      incidentId: event.params.incidentId,
      ...result,
    });
  },
);
