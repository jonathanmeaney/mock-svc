# mock-svc (mountebank-based)

![Build](https://github.com/jonathanmeaney/mock-svc/actions/workflows/build.yml/badge.svg)
![Release](https://github.com/jonathanmeaney/mock-svc/actions/workflows/release.yml/badge.svg)

## Goal

Build once → reuse in any dockerised app by mounting an external imposters file.

- Multi-stage build installs `mountebank` from npm on a Node LTS (alpine) base.
- Entry point defaults `CONFIG_PATH` to `/config/imposters.json` (JSON, JS or YAML supported).
- Overrides patch vulnerable transitive deps (see Security section).
- `test-smoke.sh` + `make smoke-run` provide a dynamic, colorised verification.

## Mode

Direct only: starts mountebank with `--configfile $CONFIG_PATH`.

## Quick start

1. Build image:

```bash
make build   # or: docker build -t mock-svc .
```

2. In your app's docker-compose:
   ```yaml
   services:
     mock-svc:
       image: mock-svc:latest
       # environment:  # (optional) omit if you use the default /config/imposters.json
       #   CONFIG_PATH: /config/imposters.js
       volumes:
         - ./mocks/imposters.js:/config/imposters.js:ro
       ports:
         - "2525:2525" # admin (optional)
         - "3101:3101" # expose the mock ports you define
         - "3102:3102"
   ```
3. Provide your own imposters file (JSON preferred): e.g. `./mocks/imposters.json` and mount it:
   `-v ./mocks/imposters.json:/config/imposters.json:ro`

- JS CommonJS config (`module.exports = { imposters: [...] }`) is also supported; it is auto-converted to JSON at runtime.
- For YAML: `-e CONFIG_PATH=/config/imposters.yml -v ./mocks/imposters.yml:/config/imposters.yml:ro`.

## Example docker-compose

```yaml
services:
  mock-svc:
    image: mock-svc:latest
    # environment:
    #   CONFIG_PATH: /config/imposters.js
    volumes:
      - ./mocks/imposters.js:/config/imposters.js:ro
    ports:
      - "2525:2525"
      - "3101:3101"
      - "3102:3102"
    restart: unless-stopped
```

## Healthcheck

The image includes a Docker `HEALTHCHECK` probing `http://localhost:2525/` for the word "mountebank".
If you prefer to disable it, override with `--no-healthcheck` or add a trivial one in compose.

## Notes

- Ensure you publish the specific service ports you define inside the imposters (e.g., 3101/3102).
- Keep `--allowInjection` enabled if you use `_behaviors.decorate`.
- For proxying, make sure the target host is reachable from within the Docker network.
- TypeScript tooling & source were removed; image is a thin wrapper over mountebank.
- `Makefile` provides build/run/smoke targets.
- GitHub Action workflow (`.github/workflows/build.yml`) can build & push on branch/tag.
  - Release workflow (`.github/workflows/release.yml`) signs images, creates SBOM & release notes.
- Licensed under MIT (see `LICENSE`).

## Make targets

| Target             | Description                                                                                  | Key Env Overrides                       |
| ------------------ | -------------------------------------------------------------------------------------------- | --------------------------------------- |
| `make build`       | Build the image (`$(IMAGE):$(TAG)`)                                                          | `IMAGE`, `TAG`                          |
| `make build-multi` | Multi-arch build & push via buildx (linux/amd64, arm64)                                      | `IMAGE`, `TAG` (must be a registry ref) |
| `make run`         | Build then run container mapping admin + example mock port; expects `./mocks/imposters.json` | `IMAGE`, `TAG`, (mount path edits)      |
| `make smoke`       | Run `test-smoke.sh` against a running instance (assumes ports 2525/3101 published)           | `MOCK_HOST`, `ADMIN_PORT`, `USER_PORT`  |
| `make push`        | Build then push to registry (requires prior `docker login`)                                  | `IMAGE`, `TAG`                          |
| `make smoke-run`   | Build, run a disposable container with dynamic host ports, execute smoke test, clean up      | same as run + smoke vars                |
| `make scan`        | Trivy scan (HIGH/CRITICAL, ignore unfixed) on built image                                    | `IMAGE`, `TAG`                          |

Override examples:

```bash
IMAGE=myrepo/mock-svc TAG=dev make build
IMAGE=myrepo/mock-svc TAG=v1.2.3 make push
MOCK_HOST=remote-host USER_PORT=3105 make smoke
```

Run without building (if already built):

```bash
docker run --rm -p 2525:2525 -p 3101:3101 \
  -v $PWD/mocks/imposters.js:/config/imposters.js:ro \
  -e CONFIG_PATH=/config/imposters.js mock-svc:latest
```

Quiet smoke test (CI-style):

```bash
QUIET=1 ./test-smoke.sh
```

Multi-arch build & push (requires BuildKit + credentials):

```bash
IMAGE=myrepo/mock-svc TAG=v1.0.0 make build-multi
```

Pin a specific mountebank version and/or Node base image:

```bash
docker build \
  --build-arg MB_VERSION=2.10.0 \
  --build-arg NODE_IMAGE=node:20.11.1-alpine \
  -t mock-svc:2.10.0 .
```

Default config resolution order:

1. Explicit `CONFIG_PATH` env var (if set)
2. Fallback `/config/imposters.json` (entrypoint internal default)
3. JS module (`*.js`) auto-converted to JSON
4. YAML supported when path ends with `.yml` or `.yaml`

## Build Arguments

| Arg          | Default           | Purpose                                                     |
| ------------ | ----------------- | ----------------------------------------------------------- |
| `MB_VERSION` | `latest`          | Which mountebank npm version to install                     |
| `NODE_IMAGE` | `node:lts-alpine` | Base image reference (override to pin exact version/digest) |

Reproducible example (pin Node digest):

```bash
docker build \
  --build-arg NODE_IMAGE=node:20.11.1-alpine@sha256:<digest> \
  --build-arg MB_VERSION=2.10.0 \
  -t mock-svc:2.10.0 .
```

## Supply Chain / Security

- Images are built multi-arch (amd64/arm64).
- Vulnerability scanning (Trivy) runs in CI (PR: informational, push: fails on HIGH/CRITICAL) and locally via `make scan`.
- SBOM (SPDX JSON) generated via Syft and uploaded as artifact; release SBOM attached to GitHub Release.
- Images are signed with cosign keyless (OIDC) – verify with:

```bash
cosign verify $YOUR_DOCKERHUB_USER/mock-svc:latest \
  --certificate-identity-regexp 'https://github.com/jonathanmeaney/mock-svc' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

- Provenance (SLSA-style attestations) enabled in release workflow (buildx provenance flag).

### Dependency Overrides

Current overrides in `package.json` mitigating reported CVEs:

```
ejs@3.1.9
cross-spawn@7.0.5
body-parser@1.20.3
jsonpath-plus@10.3.0
path-to-regexp@0.1.12
```

Remove overrides selectively once upstream `mountebank` updates; re-run `make scan` after each removal.

### Recommendations

- Commit a generated `package-lock.json` for full dependency graph reproducibility (currently omitted → semver drift possible).
- Consider pinning `NODE_IMAGE` by digest in CI for deterministic base.
- Maintain a minimal `.trivyignore` only for assessed low-risk CVEs (document rationale).
