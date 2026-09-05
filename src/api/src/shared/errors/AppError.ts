/**
 * The one error type the API throws on purpose.
 *
 * `conventions.md` §8: **the code is the contract; the message is
 * presentation.** Codes are stable and machine-readable, and they are what rule
 * tests assert. Messages are display text and *will* change — Vietnamese is
 * planned — so nothing may depend on their wording.
 *
 * ```ts
 * expect(err.code).toBe('CHAIR_DOUBLE_BOOKED')   // ← what tests assert
 * ```
 *
 * That is why `message` is optional here. Step 5c adds
 * `shared/errors/catalogue.ts` as the single machine-readable source of wording,
 * and the handler resolves `code → message` through it. Until then the code
 * doubles as its own wording. A use case that passes a message is giving a
 * default, never a guarantee.
 */

/** The response body shape, fixed by `conventions.md` §8. */
export interface ErrorResponse {
  error: {
    code: string
    message: string
    field?: string
  }
}

export interface AppErrorOptions {
  /** Stable, machine-readable, SCREAMING_SNAKE. The thing tests assert. */
  code: string
  /** HTTP status this maps to. */
  status: number
  /** Default display text. Superseded by the catalogue in step 5c. */
  message?: string
  /** The request field at fault, where the UI can point at one. */
  field?: string
  /** The underlying error, for logs. Never reaches the client. */
  cause?: unknown
}

export class AppError extends Error {
  readonly code: string
  readonly status: number
  readonly field: string | undefined

  constructor(options: AppErrorOptions) {
    // Error.message defaults to the code so a stack trace is still legible
    // before the catalogue exists.
    super(options.message ?? options.code, { cause: options.cause })
    this.name = 'AppError'
    this.code = options.code
    this.status = options.status
    this.field = options.field
  }

  /**
   * Distinguishes an AppError from any other throw without `instanceof`, which
   * fails across module realms — two copies of a package, a bundled build, a
   * worker. The handler must never mistake an internal error for a deliberate
   * one, because that would leak internals as if they were user-facing text.
   */
  static is(value: unknown): value is AppError {
    return (
      value instanceof Error &&
      'code' in value &&
      'status' in value &&
      typeof (value as AppError).code === 'string' &&
      typeof (value as AppError).status === 'number'
    )
  }

  toResponse(message: string = this.message): ErrorResponse {
    return {
      error: {
        code: this.code,
        message,
        ...(this.field === undefined ? {} : { field: this.field }),
      },
    }
  }
}

// Named constructors for the statuses this API actually uses. A bare
// `new AppError({ status: 418 })` is possible but should be suspicious in review.

/** 400 — the request itself is malformed. Shape, not business meaning. */
export const badRequest = (code: string, message?: string, field?: string): AppError =>
  new AppError({ code, status: 400, message, field })

/** 401 — no valid principal for this route group (`conventions.md` §15). */
export const unauthorized = (code: string, message?: string): AppError =>
  new AppError({ code, status: 401, message })

/** 403 — a valid principal that may not do this. */
export const forbidden = (code: string, message?: string): AppError =>
  new AppError({ code, status: 403, message })

/** 404 — no such row, or none this principal may see. */
export const notFound = (code: string, message?: string): AppError =>
  new AppError({ code, status: 404, message })

/**
 * 409 — the request is valid but collides with existing state: a duplicate
 * `national_id`, a chair already booked. The client can retry differently.
 */
export const conflict = (code: string, message?: string, field?: string): AppError =>
  new AppError({ code, status: 409, message, field })

/**
 * 422 — well-formed, but a business rule refuses it. This is where the ported
 * catalogue rules land, and where a named CHECK violation arrives from step 5b.
 */
export const unprocessable = (code: string, message?: string, field?: string): AppError =>
  new AppError({ code, status: 422, message, field })
