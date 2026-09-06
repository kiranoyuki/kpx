# KPX

Dental clinic management. Four independent packages, and **no root
`package.json`** — so `npm run <anything>` from this directory fails with
`ENOENT ... /KPX/package.json`. That is expected. Run commands from a package.

```
db/              @kpx/db          the database layer, and the schema itself
src/api/         @kpx/api         Fastify + Kysely, port 3000
src/ui-clinic/   @kpx/ui-clinic   internal app for staff, port 5173
src/ui-patient/  (Phase P)        public app for patients, port 5174
```

Not an npm workspace, deliberately: a workspace means one root lockfile, which
two people working in parallel rewrite at once, producing a conflict in the file
that is worst to merge. See `Design/plan/checklist.md`.

## Running it

Each package installs and runs on its own. `@kpx/api` builds `@kpx/db` for you.

```sh
cd src/api      && npm ci && npm run dev     # http://localhost:3000/api/health
cd src/ui-clinic && npm ci && npm run dev    # http://localhost:5173
```

Every package has the same four scripts:

```sh
npm run typecheck
npm run lint
npm test
npm run build
```

## The database

`db/kpx.db` is a **build artefact**; the `.sql` module files are the source of
truth. It is gitignored, so a fresh clone has to build it:

```sh
db/build.sh
```

After a rebuild, disconnect and reconnect any SQL client — Refresh alone reuses
the old file handle and shows a ghost of the previous database.

Regenerate the Kysely types after a schema change:

```sh
cd db && npm run codegen
```

## Configuration

`src/api/.env` is loaded if present; `src/api/.env.example` lists the variables.
Nothing is required to run locally.

**Authentication is a stub.** It trusts an `X-Acting-User` header, which anyone
can set, and exists so the backend can be built before real auth lands — see
`Design/plan/decisions.md`. It is on by default outside production and **off in
production**, where the app refuses to start rather than trust a header. To act
as a real staff member from the seed:

```sh
curl -H "X-Acting-User: $(sqlite3 db/kpx.db \
  "SELECT id FROM v_portal_access WHERE staff_portal='yes' LIMIT 1;")" \
  localhost:3000/api/clinic/...
```

## Where the plan lives

| | |
|---|---|
| `Design/plan/checklist.md` | the build, step by step, with what proves each one |
| `Design/plan/conventions.md` | standing rules that apply to every step |
| `Design/plan/decisions.md` | what changed since, and why |
| `Design/plan/open-questions.md` | what cannot be guessed and is blocking |
| `Design/rule-catalogue.md` | the 89 rules the API owns, and why each exists |
| `Design/core-entities/` | the 41 entities and how they relate |
