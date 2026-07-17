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

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const { SQSClient, SendMessageCommand } = require("@aws-sdk/client-sqs");

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
