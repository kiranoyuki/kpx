import js from '@eslint/js'
import globals from 'globals'
import tseslint from 'typescript-eslint'

import { noAmbientTime, noAwaitInTransaction } from '../../db/eslint.rules.js'

export default tseslint.config(
  {
    ignores: ['dist/**', 'node_modules/**'],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    languageOptions: {
      globals: {
        ...globals.node,
      },
    },
    rules: {
      ...noAwaitInTransaction,
    },
  },
  {
    // Where business logic lives. Ambient time makes a rule untestable (§4).
    files: ['src/shared/**/*.ts', 'src/modules/**/*.ts'],
    rules: {
      ...noAmbientTime,
    },
  },
  {
    // The one module allowed to read the machine clock — that is its whole job.
    files: ['src/shared/clock.ts'],
    rules: {
      // Re-stated rather than switched off: dropping no-restricted-syntax
      // entirely would take the transaction guard with it.
      ...noAwaitInTransaction,
    },
  },
)
