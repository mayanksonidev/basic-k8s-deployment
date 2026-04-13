require('dotenv').config();

const express = require('express');
const app = express();
const port = process.env.PORT || 3000;

// enable JSON parsing so req.body works for application/json
app.use(express.json());

// your existing env‐driven messages
const message1 = process.env.MESSAGE1 || "";
const message2 = process.env.MESSAGE2 || "";
const username = process.env.USERNAME || "";
const password = process.env.PASSWORD || "";

// all your GET routes
app.get('/', (req, res) => {
  res.send(`<h1>Hello Developers!</h1>`);
});

app.get('/message1', (req, res) => {
  res.send(`<h1>Hello Developers! ${message1}</h1>`);
});

app.get('/message2', (req, res) => {
  res.send(`<h1>Hello Developers! ${message2}</h1>`);
});

app.get('/secrets', (req, res) => {
  res.send(`
    <h1>Username: ${username}</h1>
    <h1>Password: ${password}</h1>
  `);
});


// Probes
const startTime = Date.now();

app.get('/healthz', (req, res) => {
  const elapsed = (Date.now() - startTime) / 1000;

  // Startup Probe: Fail for the first 30 seconds
  if (elapsed < 30) {
    console.log(`[Startup] Failed. Elapsed: ${elapsed.toFixed(1)}s`);
    return res.status(500).send('Startup Check Failed');
  }

  // Liveness Probe: Fail between 35s and 50s (simulate a temporary gltich)
  if (elapsed > 35 && elapsed < 50) {
    console.log(`[Liveness] Failed. Elapsed: ${elapsed.toFixed(1)}s`);
    return res.status(500).send('Liveness Check Failed');
  }

  // Otherwise healthy
  res.status(200).send('OK');
});

app.get('/readyz', async (req, res) => {
  const elapsed = (Date.now() - startTime) / 1000;

  // Readiness Probe: Fail for the first 60 seconds (simulate loading data)
  if (elapsed < 60) {
    console.log(`[Readiness] Failed. Elapsed: ${elapsed.toFixed(1)}s`);
    return res.status(500).send('Readiness Check Failed');
  }

  res.status(200).send('OK');
});

app.listen(port, () => {
  console.log(`🚀 Server listening on port ${port}`);
});
