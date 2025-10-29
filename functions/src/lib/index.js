"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.flightStatusFlow = exports.summarizeFlow = exports.chatFlow = void 0;
const v2_1 = require("firebase-functions/v2"); // Import this before using it
const app_1 = require("firebase-admin/app");
// Set global options first
(0, v2_1.setGlobalOptions)({
    maxInstances: 10,
    region: "us-central1",
});
// Initialize Firebase Admin SDK
(0, app_1.initializeApp)();
// Import and re-export your flows from genkit-sample
const genkit_sample_1 = require("./genkit-sample");
Object.defineProperty(exports, "chatFlow", { enumerable: true, get: function () { return genkit_sample_1.chatFlow; } });
Object.defineProperty(exports, "summarizeFlow", { enumerable: true, get: function () { return genkit_sample_1.summarizeFlow; } });
Object.defineProperty(exports, "flightStatusFlow", { enumerable: true, get: function () { return genkit_sample_1.flightStatusFlow; } });
//# sourceMappingURL=index.js.map