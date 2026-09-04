import Fastify, { type FastifyInstance } from 'fastify'

// Builds a fully configured Fastify instance but never calls listen() — that
// is what makes it testable via fastify.inject() (see app.test.ts) and keeps
// main.ts the only place that binds a port.
export function buildApp(): FastifyInstance {
  const app = Fastify({ logger: true })

  app.get('/api/health', async () => {
    return { status: 'ok' }
  })

  return app
}
