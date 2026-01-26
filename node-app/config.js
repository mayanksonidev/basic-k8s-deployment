// config.js
require('dotenv').config();

const mysql = require('mysql2');

// K8s service name for your MySQL database
const DB_HOST = process.env.DB_HOST || 'mysql-service';
// K8s service port (default MySQL port)
const DB_PORT = process.env.DB_PORT || 3306;
// Credentials & DB name from env (in k8s, inject via Secret)
const DB_USER     = process.env.DB_USER     || 'appuser';
const DB_PASSWORD = process.env.DB_PASSWORD || 'apppassword';
const DB_NAME     = process.env.DB_NAME     || 'appdb';
// Optional pool size
const DB_CONN_LIMIT = parseInt(process.env.DB_CONN_LIMIT, 10) || 10;

const pool = mysql.createPool({
  host:     DB_HOST,
  port:     DB_PORT,
  user:     DB_USER,
  password: DB_PASSWORD,
  database: DB_NAME,
  waitForConnections: true,
  connectionLimit:    DB_CONN_LIMIT,
  queueLimit:         0
});

module.exports = pool;
