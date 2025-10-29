import { setGlobalOptions } from "firebase-functions/v2"; // Import this before using it
import { initializeApp } from "firebase-admin/app";

// Set global options first
setGlobalOptions({
  maxInstances: 10,
  region: "us-central1",
});

// Initialize Firebase Admin SDK
initializeApp();

// Import and re-export your flows from genkit-sample
import {
  chatFlow,
  summarizeFlow,
  flightStatusFlow,
} from "./genkit-sample";

// Export flows so they are deployed
export {
  chatFlow,
  summarizeFlow,
  flightStatusFlow,
};
