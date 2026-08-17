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

## Alta de un proyecto nuevo

Siete pasos. Los primeros cuatro son del proyecto y de Cloudflare; recien el
quinto toca este repo.

### 1. Scripts npm

El pipeline invoca estos verbos por nombre. Son convencion, no inputs: que todos
los proyectos expongan los mismos es la mitad del valor de tener una base.

```json
{
  "scripts": {
    "lint": "eslint .",
    "test": "vitest run",
    "build": "vite build",
    "build:preview": "vite build --mode preview",
    "deploy:cf": "wrangler deploy",
    "deploy:preview": "wrangler versions upload --preview-alias dev"
  }
}
```

Dos detalles que rompen cosas si se pasan por alto:

- **`deploy:cf` y `deploy:preview` no tienen que buildear.** El pipeline
  restaura el bundle que ya construyo, lintó y midio en el job `check`. Si el
  script hace `npm run build && wrangler deploy`, ese trabajo se tira y se
  despliega un artefacto que nadie testeo.
- **`deploy:preview` necesita `--preview-alias`.** Sin eso se sube una version
  pero ningun alias apunta a ella, y `preview_url` queda mostrando la anterior.

Ambos scripts reciben `--tag` y `--message` por `--`, asi que tienen que
terminar en el comando de wrangler, no en un `&&`.

### 2. Archivos que el proyecto tiene que tener

```
.node-version          Version de Node. La leen el CI y Cloudflare Workers Builds
.env.preview           Lo lee `npm run build:preview`
wrangler.toml/.jsonc   Config del Worker
```

### 3. Crear el Worker en Cloudflare

Un primer deploy manual desde la maquina, para que el Worker exista y la URL
resuelva:

```bash
npx wrangler deploy
```

Anotar la URL que imprime: es el `production_url` del paso 5. La de preview es
la misma con el prefijo del alias (`https://dev-<worker>.<subdominio>.workers.dev`).

### 4. Environments y secretos en GitHub

En **Settings → Environments** del proyecto, crear dos: `preview` y
`production`. En cada uno, como **secreto de environment** (no de repositorio):

```
CLOUDFLARE_API_TOKEN     Token con permiso Edit Cloudflare Workers
CLOUDFLARE_ACCOUNT_ID
```

Que sean de environment y no de repositorio es lo que impide que el job de
preview pueda leer el token de produccion. Si se cargan a nivel repositorio el
aislamiento desaparece, aunque el pipeline siga andando.

En `production` conviene ademas marcar **Required reviewers**. El rollback
hereda esa proteccion, que es lo correcto incluso bajo presion: un rollback a la
version equivocada es un segundo incidente.

### 5. Copiar los dos archivos

```bash
cp examples/ci.yml       tu-proyecto/.github/workflows/ci.yml
cp examples/rollback.yml tu-proyecto/.github/workflows/rollback.yml
```

Reemplazar `NOMBRE-DEL-WORKER.TU-SUBDOMINIO` por lo del paso 3, en los dos
archivos. Si el repo usa `master` en vez de `main`, descomentar
`production_branch` / `preview_branch` en `ci.yml` **y** ajustar la lista de
`on.push.branches`, que es independiente.

### 6. Ramas

El modelo asume dos: `main` (o `master`) para produccion y `dev` para preview.
Crear `dev` si no existe, y proteger la de produccion exigiendo PR — es lo que
hace que el mensaje del merge commit quede util en el tab Deployments de
Cloudflare.

### 7. Primer run

Pushear a `dev` y mirar el run. En orden, tiene que verse:

1. `check` verde
2. `preview` desplegando y el smoke test en 200
3. El link en el step summary y en la pestaña Environments

Si `check` pasa pero `preview` no arranca, `preview_branch` no coincide con la
rama. Si el smoke test falla con la URL vieja, falta el `--preview-alias` del
paso 1.

Una vez que `dev` funciona, mergear a produccion y confirmar que `deploy`
corre y que el rollback aparece en la pestaña Actions.

## Si algo falla en el primer run

| Sintoma | Causa casi siempre |
|---|---|
| `workflow was not found` | El ref del `uses:` no existe, o el repo base dejo de ser publico |
| 401 / 403 en el deploy | Los secretos estan a nivel repositorio y no de environment, o al token le falta Edit Workers |
| `check` verde y ningun deploy | `production_branch`/`preview_branch` no coinciden con `on.push.branches` |
| Smoke test 200 pero sirve codigo viejo | `deploy:preview` sin `--preview-alias`, o el deploy fallo en silencio |
| Smoke test nunca llega a 200 | Falta un binding o un secreto del Worker: responde 500 desde el primer hit |
| `Permission denied` en un script | Se perdio el bit +x; las actions invocan por `bash`, asi que no deberia pasar |

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

## Por que no hay bloque `secrets:`

Los requisitos del proyecto consumidor —scripts npm, archivos, environments—
estan en **Alta de un proyecto nuevo**, arriba. Falta uno de ellos y el
pipeline falla; ninguno tiene default.

Lo que si vale explicar aca es una ausencia: `ci.yml` no declara un bloque
`secrets:` de `workflow_call`. Los tokens son secretos de environment y los
jobs los alcanzan declarando `environment:`. Declararlos tambien en
`workflow_call` los pisaria con string vacio cada vez que un caller se olvidara
de pasarlos, y eso falla como un 401 a mitad de un deploy en vez de como un
input faltante.

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
