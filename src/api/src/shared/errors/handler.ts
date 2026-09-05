/**
 * The single exit for every error leaving the API.
 *
 * One response shape, fixed by `conventions.md` §8:
 *
 * ```json
 * { "error": { "code": "CHAIR_DOUBLE_BOOKED", "message": "…", "field": "chairId" } }
 * ```
 *
 * Two rules this file exists to keep:
 *
 * 1. **A deliberate error keeps its code and status.** That is the contract the
 *    UI and the rule tests read.
 * 2. **Everything else is a 500 that says nothing.** An unexpected throw is a
 *    bug, and its message may carry a file path, a SQL fragment or a row's
 *    contents. It is logged in full and reported as `INTERNAL`.
 *
 * Step 5c inserts the catalogue between the code and the wording; the shape
 * below does not change when it does.
 */

import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify'

import { AppError, type ErrorResponse } from './AppError.js'

/** Reported when an unexpected throw reaches the handler. */
export const INTERNAL_ERROR_CODE = 'INTERNAL'
/** Reported for a route that does not exist. */
export const NOT_FOUND_CODE = 'NOT_FOUND'
/** Reported when Fastify's own schema validation rejects the request. */
export const VALIDATION_FAILED_CODE = 'VALIDATION_FAILED'

const internalResponse: ErrorResponse = {
  error: { code: INTERNAL_ERROR_CODE, message: 'Internal server error' },
}

/** Fastify tags its own schema failures; they are the client's fault, not ours. */
function isValidationError(error: unknown): boolean {
  return (
    typeof error === 'object' &&
    error !== null &&
    'validation' in error &&
    (error as { validation?: unknown }).validation !== undefined
  )
}

export function registerErrorHandler(app: FastifyInstance): void {
  app.setErrorHandler((error: unknown, request: FastifyRequest, reply: FastifyReply) => {
    if (AppError.is(error)) {
      // Deliberate: the code and status are the contract. Logged at warn —
      // it is a refused request, not a fault.
      request.log.warn({ err: error, code: error.code }, 'request refused')
      void reply.status(error.status).send(error.toResponse())
      return
    }

    if (isValidationError(error)) {
      const message = error instanceof Error ? error.message : 'Request validation failed'
      request.log.warn({ err: error }, 'request failed validation')
      void reply.status(400).send({ error: { code: VALIDATION_FAILED_CODE, message } })
      return
    }

    // Unexpected. Log everything, send nothing: the message could carry a file
    // path, a SQL fragment, or the contents of a row.
    request.log.error({ err: error }, 'unhandled error')
    void reply.status(500).send(internalResponse)
  })

  app.setNotFoundHandler((request: FastifyRequest, reply: FastifyReply) => {
    void reply.status(404).send({
      error: { code: NOT_FOUND_CODE, message: `Route ${request.method} ${request.url} not found` },
    })
  })
}
