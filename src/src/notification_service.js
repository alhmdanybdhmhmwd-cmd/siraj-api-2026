import { createPushProvider } from "./runtime_adapters.js";

const notificationEncoder = new TextEncoder();

function notificationBase64Url(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/**
 * Firebase Cloud Messaging delivery boundary.
 * Keeps credential signing, preference checks and token maintenance outside
 * the HTTP route module; transport, crypto, clock and logging are injectable.
 */
export async function sendBarqPushNotification(
  env,
  recipientId,
  senderId,
  senderName,
  messageText,
  options = {},
  dependencies = {}
) {
  const category = ["groups", "statuses"].includes(options.category) ? options.category : "messages";
  const pushType = category === "groups" ? "group_message"
    : category === "statuses" ? "status_update" : "direct_message";
  const logger = dependencies.logger || console;
  if (!env?.FCM_SERVICE_ACCOUNT_JSON) {
    logger.warn?.("BARQ push delivery skipped: FCM_SERVICE_ACCOUNT_JSON is not configured");
    return;
  }
  const cryptoImpl = dependencies.cryptoImpl || globalThis.crypto;
  const nowProvider = dependencies.now || Date.now;
  let pushProvider;
  try {
    pushProvider = createPushProvider(dependencies.fetchImpl || globalThis.fetch);
    const account = JSON.parse(env.FCM_SERVICE_ACCOUNT_JSON);
    const now = Math.floor(nowProvider() / 1000);
    const pem = String(account.private_key || "").replace(/\\n/g, "\n");
    const keyBytes = Uint8Array.from(
      atob(pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "")),
      c => c.charCodeAt(0)
    );
    const signingKey = await cryptoImpl.subtle.importKey(
      "pkcs8", keyBytes,
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
      false, ["sign"]
    );
    const assertionHeader = notificationBase64Url(notificationEncoder.encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
    const assertionPayload = notificationBase64Url(notificationEncoder.encode(JSON.stringify({
      iss: account.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: account.token_uri || "https://oauth2.googleapis.com/token",
      iat: now, exp: now + 3600
    })));
    const unsigned = assertionHeader + "." + assertionPayload;
    const signature = await cryptoImpl.subtle.sign("RSASSA-PKCS1-v1_5", signingKey, notificationEncoder.encode(unsigned));
    const assertion = unsigned + "." + notificationBase64Url(new Uint8Array(signature));
    const tokenResponse = await pushProvider.request(account.token_uri || "https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion
      })
    });
    if (!tokenResponse.ok) throw new Error("FCM OAuth token request failed: " + tokenResponse.status);
    const tokenData = await tokenResponse.json();
    const projectId = account.project_id || env.FCM_PROJECT_ID;
    if (!projectId || !tokenData.access_token) throw new Error("FCM project or access token missing");

    await env.DB.prepare(`
      CREATE TABLE IF NOT EXISTS notification_preferences (
        user_id TEXT PRIMARY KEY,
        messages INTEGER NOT NULL DEFAULT 1,
        groups INTEGER NOT NULL DEFAULT 1,
        statuses INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    `).run();
    const pref = await env.DB.prepare(
      "SELECT " + category + " AS enabled FROM notification_preferences WHERE user_id = ?"
    ).bind(recipientId).first();
    if (pref && pref.enabled === 0) return;

    await env.DB.prepare(`
      CREATE TABLE IF NOT EXISTS device_tokens (
        user_id TEXT NOT NULL,
        fcm_token TEXT PRIMARY KEY,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
      )
    `).run();
    const devices = await env.DB.prepare(
      "SELECT fcm_token FROM device_tokens WHERE user_id = ?"
    ).bind(recipientId).all();
    if (!(devices.results || []).length) {
      logger.warn?.("BARQ push delivery skipped: recipient has no registered devices");
      return;
    }

    const preview = String(messageText || "").slice(0, 120);
    await Promise.all((devices.results || []).map(async device => {
      const response = await pushProvider.request(
        `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(projectId)}/messages:send`,
        {
          method: "POST",
          headers: {
            "Authorization": "Bearer " + tokenData.access_token,
            "Content-Type": "application/json"
          },
          body: JSON.stringify({
            message: {
              token: device.fcm_token,
              notification: {
                title: category === "groups"
                  ? "رسالة في " + String(options.groupName || "مجموعة برق").slice(0, 65)
                  : category === "statuses"
                    ? "SPARK جديد من " + String(senderName || "مستخدم برق").slice(0, 80)
                    : "رسالة من " + String(senderName || "مستخدم برق").slice(0, 80),
                body: category === "statuses" ? "شارك لحظة جديدة في SPARK" : preview || "لديك رسالة جديدة"
              },
              data: {
                type: pushType,
                senderId: String(senderId || ""),
                ...(category === "groups" ? { groupId: String(options.groupId || "") } : {}),
                ...(category === "statuses" && options.statusId
                  ? { statusId: String(options.statusId) } : {})
              },
              android: { priority: "HIGH", notification: { channel_id: category === "groups" ? "barq_groups" : category === "statuses" ? "barq_statuses" : "barq_messages" } }
            }
          })
        }
      );
      if (!response.ok) {
        const detail = await response.clone().text().catch(() => "");
        // INVALID_ARGUMENT can describe a malformed message payload, not
        // necessarily a dead registration token. Revoke only explicit UNREGISTERED.
        if (response.status === 404 && /UNREGISTERED/i.test(detail)) {
          await env.DB.prepare("DELETE FROM device_tokens WHERE fcm_token = ?")
            .bind(device.fcm_token).run();
        } else {
          logger.error("FCM message send failed:", response.status, detail.slice(0, 300));
        }
      }
    }));
  } catch (error) {
    logger.error("Barq push delivery failed:", error);
  }
}
