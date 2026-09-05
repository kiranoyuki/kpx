import { buildApp } from './app.js'
import { config } from './config.js'

const app = buildApp()

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
  }
}

process.on('SIGINT', () => {
  void shutdown('SIGINT')
})
process.on('SIGTERM', () => {
  void shutdown('SIGTERM')
})

void start()
