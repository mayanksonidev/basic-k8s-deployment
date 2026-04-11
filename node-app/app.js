require('dotenv').config();

const express = require('express');
const pool = require('./config');       // your MySQL pool
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

  try {
    // Check DB connection
    await pool.promise().query('SELECT 1');
    res.status(200).send('OK');
  } catch (err) {
    console.error('Readiness check failed:', err);
    res.status(500).send('Not Ready');
  }
});

/**
 * POST /users
 * Body: { "name": "...", "email": "..." }
 * Inserts a new record into the `users` table.
 */
app.post('/users', async (req, res) => {
  const { name, email } = req.body;
  if (!name || !email) {
    return res.status(400).json({ error: 'Both name and email are required.' });
  }
  try {
    const [result] = await pool
      .promise()
      .execute(
        'INSERT INTO users (name, email) VALUES (?, ?)',
        [name, email]
      );

    res.status(201).json({
      message: 'User created successfully',
      user: { id: result.insertId, name, email }
    });
  } catch (err) {
    console.error('Error inserting user:', err);
    res.status(500).json({ error: 'Error inserting into database.' });
  }
});

/**
 * GET /users
 * 
 * Queries the `users` table and returns an HTML page showing a table of all users.
 */
app.get('/users', async (req, res) => {
  try {
    // 1) Fetch all users from the database
    const [rows] = await pool
      .promise()
      .query('SELECT id, name, email FROM users');

    // 2) Build an HTML string with a styled table
    let html = `
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>Users List</title>
      </head>
      <body>
        <h1>List of Users</h1>
        <table>
          <thead>
            <tr>
              <th>ID</th>
              <th>Name</th>
              <th>Email</th>
            </tr>
          </thead>
          <tbody>
    `;
    rows.forEach(user => {
      html += `
            <tr>
              <td>${user.id}</td>
              <td>${user.name}</td>
              <td>${user.email}</td>
            </tr>
      `;
    });

    html += `
          </tbody>
        </table>
      </body>
      </html>
    `;

    // 4) Send the complete HTML page
    res.send(html);

  } catch (err) {
    console.error('Error fetching users:', err);
    res.status(500).send('<h2>Internal Server Error</h2><p>Unable to retrieve users.</p>');
  }
});

async function initializeDatabase() {

  const createUsersTableSQL = `
    CREATE TABLE IF NOT EXISTS users (
      id    INT AUTO_INCREMENT PRIMARY KEY,
      name  VARCHAR(255) NOT NULL,
      email VARCHAR(255) NOT NULL
    )
    ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
  `;

  try {
    await pool.promise().execute(createUsersTableSQL);
    console.log('✅ Ensured `users` table exists (and any others you add).');
  } catch (err) {
    console.error('❌ Error ensuring required tables exist:', err);
    throw err; // rethrow so that init() catches and aborts startup
  }
}

async function init() {
  try {

    const connection = await pool.promise().getConnection();
    connection.release();
    console.log('✅ Connected to MySQL');

    await initializeDatabase();

    // now start the server
    app.listen(port, () => {
      console.log(`🚀 Server listening on port ${port}`);
    });
  } catch (err) {
    console.error('❌ Unable to connect to MySQL:', err);
    process.exit(1);
  }
}

// call it
init();
