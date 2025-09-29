IMAGE ?= mock-svc
TAG ?= latest
DOCKER ?= docker

build:
	$(DOCKER) build -t $(IMAGE):$(TAG) .

build-multi:
	$(DOCKER) buildx build --platform linux/amd64,linux/arm64 -t $(IMAGE):$(TAG) --push .

run: build
	$(DOCKER) run --rm -p 2525:2525 -p 3101:3101 -v $$PWD/mocks/imposters.json:/config/imposters.json:ro -e CONFIG_PATH=/config/imposters.json $(IMAGE):$(TAG)

smoke:
	./test-smoke.sh

smoke-run: build
	@echo "Cleaning up any previous smoke container..."
	@$(DOCKER) rm -f $(IMAGE)-smoke >/dev/null 2>&1 || true
	@echo "Starting disposable container with dynamic port mapping..."
	@cid=$$($(DOCKER) run -d --name $(IMAGE)-smoke -p 2525 -p 3101 -v $$PWD/mocks/imposters.json:/config/imposters.json:ro -e CONFIG_PATH=/config/imposters.json $(IMAGE):$(TAG)) || { echo "Failed to start container" >&2; exit 125; }; \
	 echo "Container ID: $$cid";
	@echo "Waiting for ports to be assigned..."
	@tries=0; \
	 while [ $$tries -lt 10 ]; do \
	   admin_line=`$(DOCKER) port $(IMAGE)-smoke 2525/tcp 2>/dev/null | head -n1` || true; \
	   user_line=`$(DOCKER) port $(IMAGE)-smoke 3101/tcp 2>/dev/null | head -n1` || true; \
	   if [ -n "$$admin_line" ] && [ -n "$$user_line" ]; then \
	     break; \
	   fi; \
	   sleep 0.5; \
	   tries=`expr $$tries + 1`; \
	 done; \
	 if [ -z "$$admin_line" ] || [ -z "$$user_line" ]; then \
	   echo "Failed to obtain mapped ports" >&2; \
	   $(DOCKER) logs $(IMAGE)-smoke || true; \
	   $(DOCKER) rm -f $(IMAGE)-smoke >/dev/null 2>&1 || true; \
	   exit 126; \
	 fi; \
	 admin_port=`echo $$admin_line | awk -F: '{print $$2}'`; \
	 user_port=`echo $$user_line | awk -F: '{print $$2}'`; \
	 echo "Discovered host admin port: $$admin_port, user port: $$user_port"; \
	 echo "Waiting for mountebank readiness..."; \
	 attempts=0; \
	 until curl -s http://localhost:$$admin_port/ >/dev/null 2>&1 || [ $$attempts -ge 20 ]; do sleep 0.3; attempts=`expr $$attempts + 1`; done; \
	 if MOCK_HOST=localhost ADMIN_PORT=$$admin_port USER_PORT=$$user_port ./test-smoke.sh; then \
	   $(DOCKER) rm -f $(IMAGE)-smoke >/dev/null 2>&1; echo "Smoke test passed and container removed."; \
	 else \
	   rc=$$?; echo "Smoke test failed; container logs:"; $(DOCKER) logs $(IMAGE)-smoke; $(DOCKER) rm -f $(IMAGE)-smoke >/dev/null 2>&1; exit $$rc; \
	 fi

push: build
	$(DOCKER) push $(IMAGE):$(TAG)

.PHONY: build build-multi run smoke smoke-run push
