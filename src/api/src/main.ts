import { buildApp } from './app.js'
import { config } from './config.js'
import { openDatabase } from './db/connection.js'

// The one long-lived handle for this process. Opened before the app so a bad
// DATABASE_PATH fails here, at startup, rather than on the first request.
const sqlite = openDatabase(config.databasePath)

const app = buildApp({ sqlite })

async function start(): Promise<void> {
  try {
    await app.listen({ port: config.port, host: config.host })
  } catch (err) {
    app.log.error(err)
    process.exitCode = 1
  }
}

let shuttingDown = false

async function shutdown(signal: NodeJS.Signals): Promise<void> {
  if (shuttingDown) return
  shuttingDown = true

  app.log.info(`Received ${signal}, shutting down`)
  try {
    await app.close()
    process.exitCode = 0
  } catch (err) {
    app.log.error(err)
    process.exitCode = 1
  } finally {
    // After the server, so no request can be mid-query. better-sqlite3 is
    // synchronous, so this also checkpoints and removes the -wal and -shm files.
    sqlite.close()
  }
}

process.on('SIGINT', () => {
  void shutdown('SIGINT')
})
process.on('SIGTERM', () => {
  void shutdown('SIGTERM')
})

void start()
