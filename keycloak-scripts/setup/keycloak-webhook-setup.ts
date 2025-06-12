import fetch, { Response } from "node-fetch";

const KEYCLOAK_HOSTNAME = process.env.KEYCLOAK_BASE_URL || "http://localhost"; // Expecting http://keycloak or http://localhost
const KEYCLOAK_API_PORT = process.env.KEYCLOAK_API_PORT || "8080";
const KEYCLOAK_HEALTH_PORT = process.env.KEYCLOAK_HEALTH_PORT || "9000";

const KEYCLOAK_API_URL = `${KEYCLOAK_HOSTNAME}:${KEYCLOAK_API_PORT}/auth`;
const KEYCLOAK_HEALTH_CHECK_URL = `${KEYCLOAK_HOSTNAME}:${KEYCLOAK_HEALTH_PORT}/auth/health/ready`;

const KEYCLOAK_REALM_NAME = process.env.KEYCLOAK_REALM_NAME || "master";
const KEYCLOAK_ADMIN_USER = process.env.KEYCLOAK_ADMIN_USER;
const KEYCLOAK_ADMIN_PASSWORD = process.env.KEYCLOAK_ADMIN_PASSWORD;
const TARGET_WEBHOOK_URL = process.env.TARGET_WEBHOOK_URL;
const TARGET_WEBHOOK_SECRET = process.env.TARGET_WEBHOOK_SECRET;
const TARGET_WEBHOOK_EVENT_TYPES_STRING =
  process.env.TARGET_WEBHOOK_EVENT_TYPES || "REGISTER"; // Comma-separated

const MAX_RETRIES = 30;
const RETRY_DELAY_MS = 10000; // 10 seconds

interface KeycloakTokenResponse {
  access_token: string;
  expires_in: number;
  refresh_expires_in: number;
  token_type: string;
  scope: string;
}

interface Webhook {
  id?: string;
  enabled: boolean;
  url: string;
  secret?: string; // Secret is not returned on GET
  eventTypes: string[];
  createdBy?: string;
  createdAt?: string;
}

async function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function getKeycloakAdminToken(): Promise<string> {
  if (!KEYCLOAK_ADMIN_USER || !KEYCLOAK_ADMIN_PASSWORD) {
    throw new Error(
      "KEYCLOAK_ADMIN_USER and KEYCLOAK_ADMIN_PASSWORD must be set."
    );
  }

  const tokenEndpoint = `${KEYCLOAK_API_URL}/realms/master/protocol/openid-connect/token`;
  const params = new URLSearchParams();
  params.append("grant_type", "password");
  params.append("client_id", "admin-cli");
  params.append("username", KEYCLOAK_ADMIN_USER);
  params.append("password", KEYCLOAK_ADMIN_PASSWORD);

  console.log(`Attempting to get admin token from ${tokenEndpoint}...`);
  const response = await fetch(tokenEndpoint, {
    method: "POST",
    body: params,
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(
      `Failed to get Keycloak admin token: ${response.status} ${response.statusText} - ${errorText}`
    );
  }

  const tokenResponse = (await response.json()) as KeycloakTokenResponse;
  console.log("Successfully obtained admin token.");
  return tokenResponse.access_token;
}

async function getExistingWebhooks(adminToken: string): Promise<Webhook[]> {
  const webhooksEndpoint = `${KEYCLOAK_API_URL}/realms/${KEYCLOAK_REALM_NAME}/webhooks`;
  console.log(`Fetching existing webhooks from ${webhooksEndpoint}...`);
  const response = await fetch(webhooksEndpoint, {
    headers: { Authorization: `Bearer ${adminToken}` },
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(
      `Failed to get existing webhooks: ${response.status} ${response.statusText} - ${errorText}`
    );
  }
  const webhooks = (await response.json()) as Webhook[];
  console.log(`Found ${webhooks.length} existing webhooks.`);
  return webhooks;
}

async function createWebhook(
  adminToken: string,
  webhookPayload: Webhook
): Promise<void> {
  const webhooksEndpoint = `${KEYCLOAK_API_URL}/realms/${KEYCLOAK_REALM_NAME}/webhooks`;
  console.log(
    `Creating webhook at ${webhooksEndpoint} with URL: ${webhookPayload.url}`
  );
  const response = await fetch(webhooksEndpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${adminToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(webhookPayload),
  });

  if (response.status === 201) {
    console.log("Webhook created successfully.");
  } else {
    const errorText = await response.text();
    throw new Error(
      `Failed to create webhook: ${response.status} ${response.statusText} - ${errorText}`
    );
  }
}

async function deleteWebhook(
  adminToken: string,
  webhookId: string
): Promise<void> {
  const webhookEndpoint = `${KEYCLOAK_API_URL}/realms/${KEYCLOAK_REALM_NAME}/webhooks/${webhookId}`;
  console.log(`Deleting webhook with ID ${webhookId} at ${webhookEndpoint}...`);
  const response = await fetch(webhookEndpoint, {
    method: "DELETE",
    headers: {
      Authorization: `Bearer ${adminToken}`,
    },
  });

  if (response.status === 204) {
    console.log(`Webhook with ID ${webhookId} deleted successfully.`);
  } else {
    const errorText = await response.text();
    throw new Error(
      `Failed to delete webhook ${webhookId}: ${response.status} ${response.statusText} - ${errorText}`
    );
  }
}

async function waitForKevcloak(): Promise<void> {
  console.log(
    `Waiting for Keycloak to be ready... API base: ${KEYCLOAK_API_URL}`
  );
  console.log(`Attempting health check at: ${KEYCLOAK_HEALTH_CHECK_URL}`);

  for (let i = 0; i < MAX_RETRIES; i++) {
    try {
      const response: Response = await fetch(KEYCLOAK_HEALTH_CHECK_URL, {
        timeout: 5000,
      });
      if (response.ok) {
        const healthStatus = (await response.json()) as { status: string };
        if (healthStatus.status === "UP") {
          console.log("Keycloak is ready!");
          return;
        }
        console.log(
          `Keycloak ready check attempt ${i + 1}/${MAX_RETRIES}: Status is ${
            healthStatus.status
          }. Retrying in ${RETRY_DELAY_MS / 1000}s...`
        );
      } else {
        console.log(
          `Keycloak ready check attempt ${i + 1}/${MAX_RETRIES}: HTTP status ${
            response.status
          }. Retrying in ${RETRY_DELAY_MS / 1000}s...`
        );
      }
    } catch (error) {
      const errorMessage =
        error instanceof Error ? error.message : String(error);
      console.log(
        `Keycloak ready check attempt ${
          i + 1
        }/${MAX_RETRIES} failed: ${errorMessage}. Retrying in ${
          RETRY_DELAY_MS / 1000
        }s...`
      );
    }
    await sleep(RETRY_DELAY_MS);
  }
  throw new Error(
    `Keycloak did not become ready at ${KEYCLOAK_HEALTH_CHECK_URL} after ${MAX_RETRIES} retries.`
  );
}

async function main() {
  console.log("Starting Keycloak webhook setup...");

  if (!TARGET_WEBHOOK_URL) {
    console.error(
      "Error: TARGET_WEBHOOK_URL environment variable is not set. Exiting."
    );
    process.exit(1);
  }
  if (!TARGET_WEBHOOK_SECRET) {
    console.warn(
      "Warning: TARGET_WEBHOOK_SECRET environment variable is not set. A webhook will be created without a secret."
    );
  }

  try {
    await waitForKevcloak();
    const adminToken = await getKeycloakAdminToken();
    const existingWebhooks = await getExistingWebhooks(adminToken);

    // Delete all existing webhooks
    if (existingWebhooks.length > 0) {
      console.log(
        `Found ${existingWebhooks.length} existing webhooks. Deleting them now...`
      );
      for (const wh of existingWebhooks) {
        if (wh.id) {
          await deleteWebhook(adminToken, wh.id);
        } else {
          console.warn("Found a webhook without an ID, cannot delete it.", wh);
        }
      }
      console.log("All existing webhooks have been processed for deletion.");
    } else {
      console.log("No existing webhooks found to delete.");
    }

    const targetEventTypes = TARGET_WEBHOOK_EVENT_TYPES_STRING.split(",")
      .map((s) => s.trim())
      .filter((s) => s);
    if (targetEventTypes.length === 0) {
      console.error(
        'Error: No event types specified in TARGET_WEBHOOK_EVENT_TYPES. Defaulting to ["REGISTER"], but please configure explicitly.'
      );
      targetEventTypes.push("REGISTER"); // Default if empty, though should be configured
    }

    console.log(
      `Creating webhook for URL ${TARGET_WEBHOOK_URL} and event types [${targetEventTypes.join(
        ", "
      )}]...`
    );
    const newWebhook: Webhook = {
      enabled: true,
      url: TARGET_WEBHOOK_URL,
      secret: TARGET_WEBHOOK_SECRET, // Will be undefined if not set, which is fine for the API
      eventTypes: targetEventTypes,
    };
    await createWebhook(adminToken, newWebhook);

    console.log("Keycloak webhook setup finished successfully.");
    process.exit(0);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error(`Error during Keycloak webhook setup: ${errorMessage}`);
    console.error(error); // Log the full error object for more details
    process.exit(1);
  }
}

main();
