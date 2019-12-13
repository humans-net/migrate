SOURCE ?= file gitlab
DATABASE ?= postgres
VERSION ?= $(shell git describe --tags 2>/dev/null | cut -c 2-)
TEST_FLAGS ?=
REPO_OWNER ?= $(shell cd .. && basename "$$(pwd)")
COVERAGE_DIR ?= .coverage


build-cli: clean
	-mkdir -p ./cli/build
	cd ./cmd/migrate && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -o ../../cli/build/migrate.linux-amd64 -ldflags='-s -w -X main.Version=$(VERSION) -extldflags "-static"' -tags 'create_drop_db $(DATABASE) $(SOURCE)' .
	cd ./cmd/migrate && CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -a -o ../../cli/build/migrate.darwin-amd64 -ldflags='-s -w -X main.Version=$(VERSION) -extldflags "-static"' -tags 'create_drop_db $(DATABASE) $(SOURCE)' .

clean:
	-rm -fr ./cli/build


test-short:
	make test-with-flags --ignore-errors TEST_FLAGS='-short'


test:
	@-rm -r $(COVERAGE_DIR)
	@mkdir $(COVERAGE_DIR)
	make test-with-flags TEST_FLAGS='-v -race -covermode atomic -coverprofile $$(COVERAGE_DIR)/combined.txt -bench=. -benchmem -timeout 20m'


test-with-flags:
	@echo SOURCE: $(SOURCE)
	@echo DATABASE: $(DATABASE)

	@go test $(TEST_FLAGS) ./...


kill-orphaned-docker-containers:
	docker rm -f $(shell docker ps -aq --filter label=migrate_test)


html-coverage:
	go tool cover -html=$(COVERAGE_DIR)/combined.txt


list-external-deps:
	$(call external_deps,'.')
	$(call external_deps,'./cli/...')
	$(call external_deps,'./testing/...')

	$(foreach v, $(SOURCE), $(call external_deps,'./source/$(v)/...'))
	$(call external_deps,'./source/testing/...')
	$(call external_deps,'./source/stub/...')

	$(foreach v, $(DATABASE), $(call external_deps,'./database/$(v)/...'))
	$(call external_deps,'./database/testing/...')
	$(call external_deps,'./database/stub/...')


restore-import-paths:
	find . -name '*.go' -type f -execdir sed -i '' s%\"github.com/$(REPO_OWNER)/migrate%\"github.com/mattes/migrate%g '{}' \;


rewrite-import-paths:
	find . -name '*.go' -type f -execdir sed -i '' s%\"github.com/mattes/migrate%\"github.com/$(REPO_OWNER)/migrate%g '{}' \;


# example: fswatch -0 --exclude .godoc.pid --event Updated . | xargs -0 -n1 -I{} make docs
docs:
	-make kill-docs
	nohup godoc -play -http=127.0.0.1:6064 </dev/null >/dev/null 2>&1 & echo $$! > .godoc.pid
	cat .godoc.pid


kill-docs:
	@cat .godoc.pid
	kill -9 $$(cat .godoc.pid)
	rm .godoc.pid


open-docs:
	open http://localhost:6064/pkg/github.com/$(REPO_OWNER)/migrate


# example: make release V=0.0.0
release:
	git tag v$(V)
	@read -p "Press enter to confirm and push to origin ..." && git push origin v$(V)


define external_deps
	@echo '-- $(1)';  go list -f '{{join .Deps "\n"}}' $(1) | grep -v github.com/$(REPO_OWNER)/migrate | xargs go list -f '{{if not .Standard}}{{.ImportPath}}{{end}}'

endef


.PHONY: build-cli clean test-short test test-with-flags html-coverage \
        restore-import-paths rewrite-import-paths list-external-deps release \
        docs kill-docs open-docs kill-orphaned-docker-containers

SHELL = /bin/bash
RAND = $(shell echo $$RANDOM)

