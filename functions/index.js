/**
 * Firebase Cloud Functions for Finova App
 *
 * This function sends push notifications to all users when a new app version
 * is released. It triggers when the 'app_config/version' document is updated
 * in Firestore.
 *
 * Usage:
 * 1. Deploy this function: firebase deploy --only functions
 * 2. When releasing a new version, update the Firestore document:
 *    - Collection: app_config
 *    - Document: version
 *    - Field: latest (string) - e.g., "1.2.1"
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");

// Initialize Firebase Admin SDK
admin.initializeApp();

/**
 * Triggered when the app version document is updated in Firestore.
 * Sends a push notification to all devices subscribed to 'app_updates' topic.
 */
exports.notifyNewVersion = functions.firestore
    .document("app_config/version")
    .onUpdate(async (change, context) => {
      const newData = change.after.data();
      const oldData = change.before.data();

      const newVersion = newData.latest;
      const oldVersion = oldData.latest;

      // Only send notification if version actually changed
      if (newVersion === oldVersion) {
        console.log("Version unchanged, skipping notification");
        return null;
      }

      console.log(`Version changed: ${oldVersion} → ${newVersion}`);

      // Construct the notification message
      const message = {
        topic: "app_updates",
        notification: {
          title: "New Update Available! 🎉",
          body: `Finova ${newVersion} is now available on the App Store. Update now for the latest features!`,
        },
        data: {
          type: "app_update",
          version: newVersion,
          oldVersion: oldVersion || "",
        },
        apns: {
          headers: {
            "apns-priority": "10",
          },
          payload: {
            aps: {
              sound: "default",
              badge: 1,
              "content-available": 1,
            },
          },
        },
      };

      try {
        // Send notification to all subscribers of 'app_updates' topic
        const response = await admin.messaging().send(message);
        console.log("✅ Notification sent successfully:", response);
        console.log(`   Version: ${newVersion}`);
        console.log(`   Topic: app_updates`);

        // Optionally, log to Firestore for tracking
        await admin.firestore().collection("notification_logs").add({
          type: "app_update",
          version: newVersion,
          previousVersion: oldVersion,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
          messageId: response,
          success: true,
        });

        return response;
      } catch (error) {
        console.error("❌ Error sending notification:", error);

        // Log the error
        await admin.firestore().collection("notification_logs").add({
          type: "app_update",
          version: newVersion,
          previousVersion: oldVersion,
          sentAt: admin.firestore.FieldValue.serverTimestamp(),
          success: false,
          error: error.message,
        });

        throw error;
      }
    });

/**
 * HTTP endpoint to manually trigger a version notification (for testing).
 *
 * Usage:
 * curl -X POST https://your-region-your-project.cloudfunctions.net/sendVersionNotification \
 *   -H "Content-Type: application/json" \
 *   -d '{"version": "1.2.1"}'
 */
exports.sendVersionNotification = functions.https.onRequest(async (req, res) => {
  // Only allow POST requests
  if (req.method !== "POST") {
    res.status(405).send("Method not allowed");
    return;
  }

  const {version} = req.body;

  if (!version) {
    res.status(400).send("Missing 'version' in request body");
    return;
  }

  console.log(`Manual notification triggered for version: ${version}`);

  const message = {
    topic: "app_updates",
    notification: {
      title: "New Update Available! 🎉",
      body: `Finova ${version} is now available on the App Store. Update now for the latest features!`,
    },
    data: {
      type: "app_update",
      version: version,
    },
    apns: {
      headers: {
        "apns-priority": "10",
      },
      payload: {
        aps: {
          sound: "default",
          badge: 1,
        },
      },
    },
  };

  try {
    const response = await admin.messaging().send(message);
    console.log("✅ Manual notification sent:", response);
    res.status(200).json({
      success: true,
      messageId: response,
      version: version,
    });
  } catch (error) {
    console.error("❌ Error sending manual notification:", error);
    res.status(500).json({
      success: false,
      error: error.message,
    });
  }
});
