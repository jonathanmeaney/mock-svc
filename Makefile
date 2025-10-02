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
	@C_RESET="\033[0m"; C_CYAN="\033[36m"; C_GREEN="\033[32m"; C_YELLOW="\033[33m"; C_RED="\033[31m"; BOLD="\033[1m"; START_TS=$$(date +%s); \
	 echo -e "$$C_CYAN→ Cleaning up any previous smoke container...$$C_RESET"; \
	 $(DOCKER) rm -f $(IMAGE)-smoke >/dev/null 2>&1 || true; \
	 echo -e "$$C_CYAN→ Starting disposable container (dynamic ports)...$$C_RESET"; \
	 cid=$$($(DOCKER) run -d --name $(IMAGE)-smoke -p 2525 -p 3101 -v $$PWD/mocks/imposters.json:/config/imposters.json:ro -e CONFIG_PATH=/config/imposters.json $(IMAGE):$(TAG)) || { echo -e "$$C_RED✖ Failed to start container$$C_RESET" >&2; exit 125; }; \
	 echo -e "  Container ID: $$BOLD$$cid$$C_RESET"; \
	 echo -e "$$C_CYAN→ Resolving mapped ports...$$C_RESET"; \
	 tries=0; \
	 while [ $$tries -lt 12 ]; do \
	   admin_line=`$(DOCKER) port $(IMAGE)-smoke 2525/tcp 2>/dev/null | head -n1` || true; \
	   user_line=`$(DOCKER) port $(IMAGE)-smoke 3101/tcp 2>/dev/null | head -n1` || true; \
	   [ -n "$$admin_line" ] && [ -n "$$user_line" ] && break; \
	   sleep 0.25; tries=`expr $$tries + 1`; \
	 done; \
	 if [ -z "$$admin_line" ] || [ -z "$$user_line" ]; then \
	   echo -e "$$C_RED✖ Failed to obtain mapped ports$$C_RESET" >&2; \
	   $(DOCKER) logs $(IMAGE)-smoke || true; \
	   $(DOCKER) rm -f $(IMAGE)-smoke >/dev/null 2>&1 || true; exit 126; \
	 fi; \
	 admin_port=`echo $$admin_line | awk -F: '{print $$2}'`; \
	 user_port=`echo $$user_line | awk -F: '{print $$2}'`; \
	 echo -e "  Admin Port: $$BOLD$$admin_port$$C_RESET  User Port: $$BOLD$$user_port$$C_RESET"; \
	 echo -e "$$C_CYAN→ Waiting for admin readiness...$$C_RESET"; \
	 attempts=0; READY_START=$$(date +%s); \
	 until curl -s http://localhost:$$admin_port/ >/dev/null 2>&1 || [ $$attempts -ge 40 ]; do sleep 0.25; attempts=`expr $$attempts + 1`; done; \
	 READY_END=$$(date +%s); READY_TIME=`expr $$READY_END - $$READY_START`; \
	 if [ $$attempts -ge 40 ]; then \
	   echo -e "$$C_RED✖ Admin endpoint not ready within $$READY_TIME s$$C_RESET"; \
	   $(DOCKER) logs $(IMAGE)-smoke || true; $(DOCKER) rm -f $(IMAGE)-smoke >/dev/null 2>&1 || true; exit 127; \
	 fi; \
	 echo -e "$$C_GREEN✓ Admin ready in $$READY_TIME s$$C_RESET"; \
	 echo -e "$$C_CYAN→ Running smoke tests...$$C_RESET"; TEST_START=$$(date +%s); \
	 if MOCK_HOST=localhost ADMIN_PORT=$$admin_port USER_PORT=$$user_port ./test-smoke.sh; then \
	   TEST_END=$$(date +%s); TEST_TIME=`expr $$TEST_END - $$TEST_START`; TOTAL_TIME=`expr $$TEST_END - $$START_TS`; \
	   echo -e "$$C_GREEN✓ Smoke tests passed$$C_RESET  (tests: $$TEST_TIME s | total: $$TOTAL_TIME s)"; \
	   $(DOCKER) rm -f $(IMAGE)-smoke >/dev/null 2>&1; \
	 else \
	   rc=$$?; TEST_END=$$(date +%s); TOTAL_TIME=`expr $$TEST_END - $$START_TS`; \
	   echo -e "$$C_RED✖ Smoke tests failed (total: $$TOTAL_TIME s)$$C_RESET"; \
	   echo -e "  Fetching container logs..."; $(DOCKER) logs $(IMAGE)-smoke || true; \
	   $(DOCKER) rm -f $(IMAGE)-smoke >/dev/null 2>&1; exit $$rc; \
	 fi

push: build
	$(DOCKER) push $(IMAGE):$(TAG)

scan: build
	@which trivy >/dev/null 2>&1 || { echo "Trivy not installed (install with: brew install trivy)" >&2; exit 2; }
	@echo "Running vulnerability scan (HIGH/CRITICAL, ignore unfixed) on $(IMAGE):$(TAG)..."
	@trivy image --severity HIGH,CRITICAL --ignore-unfixed $(IMAGE):$(TAG)
	@echo "Scan complete."

.PHONY: build build-multi run smoke smoke-run push scan
