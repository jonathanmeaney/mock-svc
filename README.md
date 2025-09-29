# mock-svc (mountebank-based)

![Build](https://github.com/jonathanmeaney/mock-svc/actions/workflows/build.yml/badge.svg)
![Release](https://github.com/jonathanmeaney/mock-svc/actions/workflows/release.yml/badge.svg)

## Goal

Build once → reuse in any dockerised app by mounting an external imposters file.

- Base image digest is pinned for reproducible builds; update intentionally when you want a newer mountebank.
- A simple `test-smoke.sh` script is provided to sanity check a running instance.

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
       environment:
         CONFIG_MODE: direct
         CONFIG_PATH: /config/imposters.js
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
    environment:
      CONFIG_PATH: /config/imposters.js
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

Update pinned base image digest (will modify Dockerfile):

```bash
chmod +x scripts/update-digest.sh
scripts/update-digest.sh
```

## Supply Chain / Security

- Images are built multi-arch (amd64/arm64).
- Vulnerability scanning (Trivy) runs in CI (PR: informational, push: fails on HIGH/CRITICAL).
- SBOM (SPDX JSON) generated via Syft and uploaded as artifact; release SBOM attached to GitHub Release.
- Images are signed with cosign keyless (OIDC) – verify with:

```bash
cosign verify $YOUR_DOCKERHUB_USER/mock-svc:latest \
  --certificate-identity-regexp 'https://github.com/jonathanmeaney/mock-svc' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

- Provenance (SLSA-style attestations) enabled in release workflow (buildx provenance flag).
