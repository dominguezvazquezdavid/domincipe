# STATUS.md — Foto del estado del repositorio

> **Qué es**: resumen **fechado** del estado real del proyecto, para que una sesión nueva (persona o agente) arranque con contexto mínimo sin releer `PROJECT.md`, `AGENTS.md`, `tasks.md` y el historial de git.
> **No es fuente de verdad.** Si este fichero discrepa de lo que dicen git, `openspec/` o `PROJECT.md`, mandan ellos.
> **Caduca** en cuanto se commitea, se archiva un change o cambia el toolchain. Refréscalo con los comandos de §7 y actualiza la fecha.

**Última actualización:** 2026-11-12 · Change activo: `project-skeleton`

---

## 1. Git

- **Rama**: `feat/project-skeleton-bootstrap`. **No existe `main` local ni remota** y **nada está publicado** (sin refs en `origin`).
- **HEAD**: el commit que añade este fichero (`docs(status): add a dated state snapshot for new sessions`); usa `git log -1` para el SHA exacto. El último commit con **código/configuración** es `f6a8a62` (CRLF de scripts Windows).
- **Últimos commits con contenido** (de nuevo a viejo): `f6a8a62` CRLF de scripts Windows · `950b819` checksum de Maven · `c9d8135` Checkstyle · `838c605` Maven Wrapper · `d28c120` versiones verificadas + OpenSpec 2.0.
- **Árbol de trabajo**: limpio.
- **Remoto**: `git@github.com:dominguezvazquezdavid/domincipe.git` (SSH).
  - ⚠️ **No se puede hacer push aún**: la clave `~/.ssh/id_ed25519` tiene **passphrase** y no hay `ssh-agent` → `ssh -T git@github.com` devuelve `Permission denied (publickey)`. Solución en la sesión del usuario: `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519`.
  - Fingerprint del host GitHub (ED25519, ya en `known_hosts`): `SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU`
  - Fingerprint de la clave local: `SHA256:TAP2W0FtSDSaBeyeUybjCgY70FnDAVh/1088CS/s+2c`

## 2. Change activo (OpenSpec 2.0.0, schema `spec-driven`)

`project-skeleton` — **planificación completa (4/4 artefactos)** y `openspec validate --changes --strict` en verde.

- Artefactos en `openspec/changes/project-skeleton/`: `proposal.md`, `design.md`, `tasks.md` y 4 specs: `repo-layout`, `service-runtime`, `local-environment`, `web-shell`.
- **Tareas: 4 hechas / 32 pendientes.** Hechas: 1.1 ficheros raíz · 1.2 versiones verificadas · 1.3 Maven Wrapper · 1.4 Checkstyle.
- **Siguiente tarea: 2.1 (parent POM)** → 2.2 `scripts/verify-modules.sh` → 2.3 gate JaCoCo → 2.4 documentar la decisión D5.
- **No existe código de aplicación todavía**: sin `pom.xml`, sin `apps/`, `libs/`, `ops/`, `scripts/`, `.env.example`.

## 3. Qué hay ya en el repo

```
AGENTS.md  PROJECT.md  README.md  LICENSE  STATUS.md
.editorconfig  .gitattributes  .gitignore
.mvn/wrapper/maven-wrapper.properties     mvnw (100755)  mvnw.cmd (CRLF)
config/checkstyle/checkstyle.xml
openspec/{config.yaml, specs/, changes/project-skeleton/, changes/archive/}
.agents/skills/openspec-*/SKILL.md        (skills de OpenSpec 2.0)
```

## 4. Toolchain de esta máquina (verificado 2026-11-12)

| Herramienta | Versión | Dónde / nota |
|---|---|---|
| JDK | Temurin **21.0.13+9** | `~/.local/opt/jdk-21` |
| Maven | **3.9.16** | `~/.local/opt/apache-maven-3.9.16`; el build usa `./mvnw` (misma versión, con checksum) |
| Node / npm | **v22.23.4** / **10.9.9** | nvm (React Router 8 exige ≥ 22.22.0) |
| openspec | **2.0.0** | skills en `.agents/skills/` |
| Docker / Compose | **29.9.3** / **v5.7.1** | sin usar todavía (nada de `ops/`) |
| Checkstyle | **14.4.0** | solo CLI para validar el XML; se fijará como dependencia del plugin en 2.1 |

## 5. Decisiones cerradas (no re-discutir sin motivo nuevo)

- **Wrapper `only-script`** (default del plugin 3.2.0+): se versionan `mvnw`, `mvnw.cmd` y `maven-wrapper.properties`, **sin `maven-wrapper.jar`** → cero binarios, coherente con SBOM/Trivy de `PROJECT.md` §9.
- **`distributionSha256Sum` fijado** (`5af3b743…6e1d89ce`): si los bytes del zip de Maven no coinciden, `mvnw` aborta. Verificado con el `.sha512` publicado por Central y con prueba negativa.
- **CRLF solo para scripts de Windows**: `.editorconfig` (`[*.{cmd,bat}] end_of_line = crlf`) + `.gitattributes` (`*.cmd text eol=crlf`). Blob en LF, checkout en CRLF; no depende de `core.autocrlf`.
- **Checkstyle**: `config/checkstyle/checkstyle.xml` cubre paquete `com.domincipe`, 120 columnas, sin *star imports* y sin imports sin uso. Validado con el CLI 14.4.0 (7 violaciones esperadas en un fichero sucio, 0 en uno limpio). **`checkstyle.version=14.4.0` se fija en 2.1** porque el plugin 3.6.0 arrastra Checkstyle **9.3**, que no parsea sintaxis de Java 21.
- **`.npmrc` va en `apps/web-frontend/`** (tarea 6.1), no en la raíz: npm **no** lee el `.npmrc` de directorios superiores (verificado empíricamente).

## 6. Trampas conocidas (ya nos costaron tiempo)

- `openspec validate` **sin flags abre un menú interactivo**: usar siempre `--changes` o `--all` con `--no-interactive`. `openspec status --change <id>` sí es no interactivo.
- Regenerar el wrapper (`mvn -N wrapper:wrapper -Dmaven=3.9.16`) **borra `distributionSha256Sum`**: volver a añadirlo o pasar `-DdistributionSha256Sum=…`.
- Al subir de versión de Maven hay que cambiar `distributionUrl` **y** la suma a la vez, o el build falla (fail-closed, es lo deseado).
- Sin `pom.xml`, `./mvnw validate` no compila nada: no confundirlo con "build en verde".
- `.gitignore` mantiene `!.mvn/wrapper/maven-wrapper.jar`, residuo de plantillas que asumían el tipo `bin`; con `only-script` es innecesario.
- `README.md` §"Estado actual" y `PROJECT.md` aún no reflejan el trabajo hecho: se actualizan en las tareas 9.1 y 9.2.

## 7. Cómo refrescar esta foto

```bash
git log --oneline -5 && git status --short --branch
openspec status --change project-skeleton
openspec validate --changes --strict --no-interactive
grep -c '\[x\]' openspec/changes/project-skeleton/tasks.md   # hechas
grep -c '\[ \]' openspec/changes/project-skeleton/tasks.md   # pendientes
./mvnw -B -ntp -v | head -2
```

Después actualiza la fecha del encabezado y las secciones que hayan cambiado. Si esta foto lleva más de un change de retraso, bórrala antes que fiarte de ella.


Versiones de librerías ya decididas (detalle en `PROJECT.md` §4): Spring Boot **4.1.2**, springdoc **3.2.0**, Kafka **4.4.0**, Versity S3 Gateway **v1.11.0**, React **19.3.1**, Vite **8.3.8**, TypeScript **5.9.3**, ESLint **10.14.0**, Vitest **5.1.0**.
