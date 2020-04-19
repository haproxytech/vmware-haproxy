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

all: build

# Image URL to use all building/pushing image targets
TAG ?= latest
REGISTRY ?= # Nothing by default
IMAGE_NAME ?= swagger2openapi
ifeq (,$(REGISTRY))
IMAGE ?= $(IMAGE_NAME)
else
IMAGE ?= $(REGISTRY)/$(IMAGE_NAME)
endif

.PHONY: build
build: ## Build the image
	docker build -t $(IMAGE):$(TAG) .

.PHONY: push
push: ## Push the image
	docker push $(IMAGE):$(TAG)
