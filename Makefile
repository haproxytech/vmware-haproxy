# Copyright (c) 2020 VMware, Inc. All Rights Reserved.
# SPDX-License-Identifier: Apache-2.0

# If you update this file, please follow
# https://suva.sh/posts/well-documented-makefiles

# Ensure Make is run with bash shell as some syntax below is bash-specific
SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

## --------------------------------------
## Help
## --------------------------------------

help: ## Display this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

## --------------------------------------
## Variables
## --------------------------------------

# Initialize the version with the Git version.
VERSION ?= $(shell git describe --always --dirty)

# DataPlane API version to build
DATAPLANEAPI_REF ?= 0553265


## --------------------------------------
## Packer flags
## --------------------------------------
PACKER_FLAGS += -var='version=$(VERSION)'

# If FOREGROUND=1 then Packer will set headless to false, causing local builds
# to build in the foreground, with a UI. This is very useful when debugging new
# platforms or issues with existing ones.
ifeq (1,$(strip $(FOREGROUND)))
PACKER_FLAGS += -var="headless=false"
endif

# A list of variable files given to Packer.
PACKER_VAR_FILES := $(strip $(foreach f,$(abspath $(PACKER_VAR_FILES)),-var-file="$(f)" ))

# Initialize a list of flags to pass to Packer. This includes any existing flags
# specified by PACKER_FLAGS, as well as prefixing the list with the variable
# files from PACKER_VAR_FILES, with each file prefixed by -var-file=.
#
# Any existing values from PACKER_FLAGS take precendence over variable files.
PACKER_FLAGS := $(PACKER_VAR_FILES) $(PACKER_FLAGS)


## --------------------------------------
## OVA
## --------------------------------------
.PHONY: build-ova
build-ova: ## Builds the HAProxy load balancer OVA
	packer build $(PACKER_FLAGS) packer.json

.PHONY: verify
verify: ## Verifies the packer config
	packer validate $(PACKER_FLAGS) packer.json


## --------------------------------------
## Docker
## --------------------------------------
.PHONY: build-image
build-image: ## Builds the container image
	docker build --build-arg "DATAPLANEAPI_REF=$(DATAPLANEAPI_REF)" -t haproxy .


## --------------------------------------
## DataPlane API OpenAPI spec
## --------------------------------------
.PHONY: build-spec
build-spec: build-image
build-spec: ## Builds the DataPlane API spec
	docker run -d --rm --name haproxy -p 5556:5556 haproxy
	while ! curl \
	  --cacert example/ca.crt \
	  --cert example/client.crt --key example/client.key \
	  --user client:cert \
	  "https://localhost:5556/v2/specification" >dataplane-api-$(DATAPLANEAPI_REF)-swagger.json; do \
	  sleep 1; \
	  done
	docker kill haproxy
	swagger2openapi "dataplane-api-$(DATAPLANEAPI_REF)-swagger.json" >"dataplane-api-$(DATAPLANEAPI_REF)-openapi.json"
	rm -f "dataplane-api-$(DATAPLANEAPI_REF)-swagger.json"


## --------------------------------------
## Clean
## --------------------------------------
.PHONY: clean
clean: ## Cleans all local image caches
	rm -fr ./output

