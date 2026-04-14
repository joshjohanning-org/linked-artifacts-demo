const express = require("express");

const app = express();
const port = process.env.PORT || 3000;

app.get("/", (req, res) => {
  res.json({
    app: "linked-artifacts-demo",
    version: process.env.APP_VERSION || "unknown",
    commit: process.env.APP_COMMIT || "unknown",
    environment: process.env.APP_ENVIRONMENT || "local",
    timestamp: new Date().toISOString(),
  });
});

app.get("/health", (req, res) => {
  res.json({ status: "healthy" });
});

app.listen(port, () => {
  console.log(`linked-artifacts-demo listening on port ${port}`);
});
