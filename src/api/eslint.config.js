import js from '@eslint/js'
import globals from 'globals'
import tseslint from 'typescript-eslint'

import { noAwaitInTransaction } from '../../db/eslint.rules.js'

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
)
