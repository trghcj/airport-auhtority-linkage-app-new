// =============================================================================
// 1. Imports
// =============================================================================

import { genkit, z } from "genkit";
import { vertexAI, gemini20Flash } from "@genkit-ai/vertexai";
import { onCallGenkit, onRequest } from "firebase-functions/https";
import { defineSecret } from "firebase-functions/params";

// =============================================================================
// 2. Configuration
// =============================================================================

const apiKey = defineSecret("GOOGLE_GENAI_API_KEY");

const ai = genkit({
  plugins: [
    vertexAI({ location: "us-central1" }),
  ],
});

// =============================================================================
// 3. Flow Definition
// =============================================================================

const menuSuggestionFlow = ai.defineFlow(
  {
    name: "menuSuggestionFlow",
    inputSchema: z.string().describe("A restaurant theme").default("seafood"),
    outputSchema: z.string(),
    streamSchema: z.string(),
  },
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  async (subject: any, { sendChunk }: any) => {
    const prompt = `Suggest an item for the menu of a ${subject} themed restaurant`;

    const { response, stream } = ai.generateStream({
      model: gemini20Flash,
      prompt,
      config: { temperature: 1 },
    });

    for await (const chunk of stream) {
      sendChunk(chunk.text);
    }

    return (await response).text;
  }
);

// =============================================================================
// 4. Export Functions
// =============================================================================

export const menuSuggestion = onCallGenkit(
  { secrets: [apiKey] },
  menuSuggestionFlow
);

export const chatFlow = onRequest((_req, res) => {
  res.send("Chat Flow working!");
});

export const summarizeFlow = onRequest((_req, res) => {
  res.send("Summarize Flow working!");
});

export const flightStatusFlow = onRequest((_req, res) => {
  res.send("Flight Status Flow working!");
});
