# Makefile for fluid_list

.DEFAULT_GOAL := help

# ================================
# Help
# ================================

.PHONY: help
help: ## Show this help message
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'

# ================================
# Setup
# ================================

setup: ## Configure the Flutter SDK and fetch dependencies (package + example)
	fvm use
	fvm flutter pub get
	cd example && fvm flutter pub get

install-sdk: ## Install the Flutter SDK
	fvm install

# ================================
# Dependencies
# ================================

pub-get: ## Fetch dependencies
	fvm flutter pub get

pub-update: ## Upgrade dependencies
	fvm flutter pub upgrade

# ================================
# Development
# ================================

format: ## Format the code
	fvm dart format . --line-length=200
	fvm dart fix --apply

analyze: ## Run static analysis
	fvm flutter analyze . --no-fatal-infos

clean: ## Remove caches
	fvm flutter clean

# ================================
# Test
# ================================

test: ## Run tests
	fvm flutter test

# ================================
# Example
# ================================

example-pub-get: ## Fetch the example app's dependencies
	cd example && fvm flutter pub get

run: ## Run the example app
	cd example && fvm flutter run

.PHONY: setup install-sdk pub-get pub-update format analyze clean test example-pub-get run
