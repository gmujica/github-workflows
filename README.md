# github-workflows

Pipeline base de CI/CD para proyectos desplegados en Cloudflare Workers.
El pipeline vive aca; cada proyecto aporta un archivo de ~15 lineas que lo llama.

## Contenido

```
.github/workflows/ci.yml            Reusable: lint, test, build, preview y produccion
.github/workflows/rollback.yml      Reusable: devuelve produccion a una version anterior
.github/actions/smoke/              Composite: verifica que el Worker responde
.github/actions/worker-url/         Composite: resuelve la URL real del output de wrangler
examples/                           Los dos archivos a copiar al proyecto
```

## Como se usa

Copiar `examples/ci.yml` y `examples/rollback.yml` a `.github/workflows/` del
proyecto y ajustar las URLs. Nada mas. El `ci.yml` del proyecto queda asi:

```yaml
name: CI

on:
  push:
    branches: [master, dev]
  pull_request:

jobs:
  ci:
    uses: gmujica/github-workflows/.github/workflows/ci.yml@main
    with:
      production_url: https://mi-worker.gmujica.workers.dev
      preview_url: https://dev-mi-worker.gmujica.workers.dev
      production_branch: master   # default: main
```

## Por que composite actions y no scripts

Dentro de un reusable workflow, `actions/checkout` clona el repo **que llama**,
no este. Una ruta como `./.github/scripts/smoke.sh` resuelve contra el proyecto,
donde no existe, y falla siempre.

El runner en cambio si descarga el codigo de una action referenciada por
`uses:`. Por eso los dos scripts bash son composite actions autocontenidas
(`action.yml` + el `.sh` al lado), y no archivos que cada proyecto tenga que
copiarse.

## Inputs de `ci.yml`

| Input | Requerido | Default | |
|---|---|---|---|
| `production_url` | si | — | URL publica del Worker; fallback del smoke test |
| `preview_url` | si | — | URL del alias de preview |
| `production_branch` | no | `main` | Rama cuyos pushes despliegan |
| `preview_branch` | no | `dev` | Rama cuyos pushes suben una version |
| `node_version_file` | no | `.node-version` | |
| `bundle_limit_bytes` | no | `2500000` | Techo del bundle gzipeado |
| `run_lint` | no | `true` | `false` si el proyecto todavia no tiene lint |
| `artifact_retention_days` | no | `7` | |

`rollback.yml` toma `version_id`, `reason`, `production_url` y
`node_version_file`.

## Lo que el proyecto consumidor tiene que aportar

Los workflows asumen que existen, y fallan sin ellos:

- `.node-version` — leido por CI y por Cloudflare Workers Builds
- `.env.preview` — leido por `npm run build:preview`
- Config de wrangler (`wrangler.toml` o `wrangler.jsonc`)
- Scripts npm: `lint`, `test`, `build`, `build:preview`, `deploy:cf`, `deploy:preview`

Los nombres de los scripts npm son convencion, no inputs, a proposito: que
todos los proyectos expongan los mismos verbos es la mitad del valor de tener
una base.

## Environments y secretos

En cada proyecto, dos environments —`preview` y `production`— cada uno con sus
propios `CLOUDFLARE_API_TOKEN` y `CLOUDFLARE_ACCOUNT_ID`.

Tienen que ser **secretos de environment**, no de repositorio. Los jobs
declaran `environment:` y los leen directamente; ese es el mecanismo que impide
que el job de preview pueda tocar las credenciales de produccion. Por eso
`ci.yml` no declara un bloque `secrets:` de `workflow_call`: declararlos ahi los
pisaria con string vacio cada vez que un caller se olvidara de pasarlos, y eso
falla como un 401 a mitad de un deploy en vez de como un input faltante.

## Versionado

Los ejemplos y las referencias internas apuntan a `@main`. Eso significa que un
cambio en este repo entra en todos los proyectos en el run siguiente, sin aviso
— comodo mientras el pipeline se asienta, mal negocio despues.

Al cortar `v1` hay que actualizar, en el mismo commit:

- las tres referencias `uses: gmujica/github-workflows/.github/actions/*@main`
  dentro de `ci.yml` y `rollback.yml`
- los `uses:` de `examples/`

Un reusable workflow no puede usar expresiones en `uses:`, asi que el ref de las
actions va hardcodeado y no se puede derivar del ref con el que fue invocado.

## Modelo de despliegue

Un push a la rama de preview sube una **version** nueva del Worker sin cambiar
lo que produccion sirve. Un merge a la rama de produccion es lo unico que
despliega. Ambos jobs reutilizan el bundle que `check` ya construyo y midio.

## Rollback

Manual, desde la pestaña Actions **del proyecto** — el `workflow_dispatch` vive
en el caller justamente para que aparezca ahi. Pide el ID de version (visible en
el tab Deployments del Worker) y un motivo, que queda registrado en el run.

Un rollback no toca la rama de produccion: sigue apuntando al commit roto y hay
que revertirlo antes del proximo merge.

## Pendiente

- Verificar contra un run real el esquema ND-JSON que emite wrangler
  (`.targets` en `worker-url.sh`). Hoy el fallback tapa un desajuste por diseño,
  lo que tambien significa que lo tapa para vos.
- Que el build escriba un `version.json` con el SHA, para que el smoke test
  compruebe *que* se esta sirviendo y no solo que algo responde 200.
