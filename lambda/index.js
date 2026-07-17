// lambda/index.js
//
// SQS-triggered Lambda: consumes { postId, message } payloads pushed by the
// onRecognitionCreated Cloud Function, runs a moderation check, and writes
// the verdict back to the Firestore "recognitions" collection.
//
// Note: senderId never appears in the SQS payload (the Cloud Function
// deliberately excludes it), so this function never has access to it either
// — the anonymity boundary holds all the way through the pipeline.

const {
  ComprehendClient,
  DetectToxicContentCommand,
} = require("@aws-sdk/client-comprehend");
const {
  SecretsManagerClient,
  GetSecretValueCommand,
} = require("@aws-sdk/client-secrets-manager");
const admin = require("firebase-admin");

const AWS_REGION = process.env.AWS_REGION;
const TOXICITY_THRESHOLD = Number(process.env.TOXICITY_THRESHOLD ?? 0.5);
const FIREBASE_SECRET_ARN = process.env.FIREBASE_SECRET_ARN;
const MAX_MESSAGE_LENGTH = 500;

// Placeholder list — swap for a maintained blocklist or a dedicated
// profanity-filter package before this goes to production.
const BANNED_WORDS = ["slur1", "slur2"];

const comprehendClient = new ComprehendClient({ region: AWS_REGION });
const secretsClient = new SecretsManagerClient({ region: AWS_REGION });

// Firebase Admin SDK must only be initialized once per warm Lambda instance.
// The service account is fetched from Secrets Manager rather than a
// plaintext env var, matching the least-privilege IAM policy in
// template.yaml (the function can only read this one secret).
let firestore;
async function getFirestore() {
  if (!firestore) {
    const secret = await secretsClient.send(
      new GetSecretValueCommand({ SecretId: FIREBASE_SECRET_ARN }),
    );
    const serviceAccount = JSON.parse(secret.SecretString);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    firestore = admin.firestore();
  }
  return firestore;
}

// Cheap, synchronous checks that don't need an API call. Returns a reject
// reason string, or null if the message passes.
function ruleBasedCheck(message) {
  if (!message || !message.trim()) {
    return "empty message";
  }
  if (message.length > MAX_MESSAGE_LENGTH) {
    return "message too long";
  }
  const lower = message.toLowerCase();
  if (BANNED_WORDS.some((word) => lower.includes(word))) {
    return "banned word match";
  }
  return null;
}

// Calls Comprehend's toxicity model and returns a reject reason string, or
// null if every label scores below TOXICITY_THRESHOLD.
async function toxicityCheck(message) {
  const command = new DetectToxicContentCommand({
    LanguageCode: "en",
    TextSegments: [{ Text: message }],
  });

  const result = await comprehendClient.send(command);
  const labels = result.ResultList?.[0]?.Labels ?? [];

  const worst = labels.reduce(
    (max, label) => (label.Score > max.Score ? label : max),
    { Name: null, Score: 0 },
  );

  if (worst.Score >= TOXICITY_THRESHOLD) {
    return `toxicity: ${worst.Name} (${worst.Score.toFixed(2)})`;
  }
  return null;
}

async function moderate(message) {
  const ruleReason = ruleBasedCheck(message);
  if (ruleReason) {
    return { status: "rejected", reason: ruleReason };
  }

  const toxicityReason = await toxicityCheck(message);
  if (toxicityReason) {
    return { status: "rejected", reason: toxicityReason };
  }

  return { status: "approved", reason: null };
}

async function processRecord(record) {
  const { postId, message } = JSON.parse(record.body);

  if (!postId || typeof message !== "string") {
    console.warn(`Skipping malformed SQS record: ${record.messageId}`);
    return;
  }

  const verdict = await moderate(message);
  const db = await getFirestore();

  await db
    .collection("recognitions")
    .doc(postId)
    .update({ moderationStatus: verdict.status });

  console.log(
    `postId ${postId} -> ${verdict.status}${verdict.reason ? ` (${verdict.reason})` : ""}`,
  );
}

// Uses partial batch response so a failure on one record (e.g. a transient
// Comprehend or Firestore error) only sends that record back to SQS for
// retry, instead of reprocessing the whole batch. Requires the Lambda's
// SQS event source mapping to have FunctionResponseTypes:
// ["ReportBatchItemFailures"] configured.
exports.handler = async (event) => {
  const batchItemFailures = [];

  for (const record of event.Records) {
    try {
      await processRecord(record);
    } catch (error) {
      console.error(`Failed to process record ${record.messageId}:`, error);
      batchItemFailures.push({ itemIdentifier: record.messageId });
    }
  }

  return { batchItemFailures };
};
