#!/usr/bin/env bash
set -euo pipefail
IMAGE="bbyars/mountebank"
TAG="latest"
 echo "Fetching latest digest for $IMAGE:$TAG..." >&2
digest=$(docker pull --quiet $IMAGE:$TAG 2>/dev/null | awk '/Digest: / {print $2}' || true)
if [ -z "$digest" ]; then
  digest=$(docker inspect --format='{{index .RepoDigests 0}}' $IMAGE:$TAG | awk -F@ '{print $2}')
fi
if [ -z "$digest" ]; then
  echo "Failed to retrieve digest" >&2; exit 1
fi
echo "Latest digest: $digest" >&2
# Update Dockerfile in-place
if grep -q 'FROM bbyars/mountebank@sha256:' Dockerfile; then
  sed -i.bak -E "s|FROM bbyars/mountebank@sha256:[a-f0-9]{64}|FROM bbyars/mountebank@$digest|" Dockerfile
  rm -f Dockerfile.bak
  echo "Dockerfile updated. Review and commit." >&2
else
  echo "No pinned FROM line found; skipping." >&2
fi
