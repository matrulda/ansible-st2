# Match E2E CI (ubuntu-22.04, ansible-core 2.18.12, molecule 3.6.1, molecule-docker 1.1.0).
# Requires Python 3.11+ (ansible-core 2.18.x).
#
# Internal CA: set EXTRA_CA_BUNDLE to your CA cert (e.g. ~/SammyCA.pem) so pip and
# molecule trust internal hosts. The Makefile builds a combined bundle (system + extra)
# and sets SSL_CERT_FILE for the venv. Example:
#   make molecule-env EXTRA_CA_BUNDLE=~/SammyCA.pem

PYTHON ?= python3.11
VENV := .venv-ci
ANSIBLE_CORE := 2.18.12
MOLECULE_VER := 3.6.1
MOLECULE_DOCKER_VER := 1.1.0

# Combined CA bundle when using internal CA (system/certifi + EXTRA_CA_BUNDLE)
CA_BUNDLE := $(VENV)/.ca-bundle.crt

.PHONY: molecule-env molecule-test molecule-converge molecule-destroy help ca-bundle

help:
	@echo "Targets:"
	@echo "  make molecule-env     Create/update $(VENV) with CI deps (Python 3.11+, ansible-core $(ANSIBLE_CORE))."
	@echo "  make molecule-test    Run molecule test (default SCENARIO=ubuntu22)."
	@echo "  make molecule-converge  Run molecule converge for SCENARIO."
	@echo "  make molecule-destroy   Run molecule destroy for SCENARIO."
	@echo "Override: SCENARIO=ubuntu20  PYTHON=python3.12  EXTRA_CA_BUNDLE=~/SammyCA.pem"

# Build combined CA bundle so SSL verifies both public and internal (e.g. Artifactory) certs.
# Uses system/certifi default bundle + EXTRA_CA_BUNDLE. Only built when EXTRA_CA_BUNDLE is set.
$(CA_BUNDLE):
	@mkdir -p $(VENV)
	@if [ -n "$(EXTRA_CA_BUNDLE)" ]; then \
		extra="$(EXTRA_CA_BUNDLE)"; \
		case "$$extra" in ~*) extra="$(HOME)$${extra#\~}";; esac; \
		[ -f "$$extra" ] || { echo "EXTRA_CA_BUNDLE not found: $$extra"; exit 1; }; \
		if [ ! -f "$$extra" ]; then echo "EXTRA_CA_BUNDLE not found: $(EXTRA_CA_BUNDLE)"; exit 1; fi; \
		default=$$($(PYTHON) -c "import ssl, os; p=ssl.get_default_verify_paths(); f=getattr(p,'openssl_cafile',None); print(f if f and os.path.isfile(f) else '')" 2>/dev/null); \
		[ -n "$$default" ] || default=$$($(PYTHON) -c "import certifi; print(certifi.where())" 2>/dev/null); \
		[ -n "$$default" ] || { echo "Could not find system CA bundle (install certifi?)"; exit 1; }; \
		cat "$$default" "$$extra" > $(CA_BUNDLE); \
		echo "Using CA bundle: $(CA_BUNDLE) (system + $$extra)"; \
	else \
		: > $(CA_BUNDLE); \
	fi

$(VENV)/.stamp: requirements-ci.txt $(CA_BUNDLE)
	$(PYTHON) -c 'import sys; assert sys.version_info >= (3, 11), "Need Python 3.11+ (ansible-core 2.18)"'
	$(PYTHON) -m venv $(VENV)
	@if [ -n "$(EXTRA_CA_BUNDLE)" ] && [ -f $(CA_BUNDLE) ] && [ -s $(CA_BUNDLE) ]; then \
		export SSL_CERT_FILE="$(CURDIR)/$(CA_BUNDLE)" REQUESTS_CA_BUNDLE="$(CURDIR)/$(CA_BUNDLE)"; \
		$(VENV)/bin/pip install --upgrade pip; \
		$(VENV)/bin/pip install -r requirements-ci.txt; \
	else \
		$(VENV)/bin/pip install --upgrade pip; \
		$(VENV)/bin/pip install -r requirements-ci.txt; \
	fi
	@if [ -n "$(EXTRA_CA_BUNDLE)" ] && [ -f $(CA_BUNDLE) ] && [ -s $(CA_BUNDLE) ]; then \
		export SSL_CERT_FILE="$(CURDIR)/$(CA_BUNDLE)" REQUESTS_CA_BUNDLE="$(CURDIR)/$(CA_BUNDLE)"; \
		$(VENV)/bin/ansible-galaxy collection install -r test/requirements.yml; \
	else \
		$(VENV)/bin/ansible-galaxy collection install -r test/requirements.yml; \
	fi
	touch $(VENV)/.stamp

molecule-env: $(VENV)/.stamp
	@echo "Use: $(VENV)/bin/molecule test --scenario-name <scenario>"
	@$(VENV)/bin/ansible --version

# Ensure PATH uses CI venv so molecule and ansible-playbook both use .venv-ci
MOLECULE_PATH := $(CURDIR)/$(VENV)/bin:$(PATH)

# Export CA bundle for molecule so Ansible/requests inside molecule also trust internal CA
molecule-test: molecule-env
	@if [ -n "$(EXTRA_CA_BUNDLE)" ] && [ -f $(CA_BUNDLE) ] && [ -s $(CA_BUNDLE) ]; then \
		export SSL_CERT_FILE="$(CURDIR)/$(CA_BUNDLE)" REQUESTS_CA_BUNDLE="$(CURDIR)/$(CA_BUNDLE)"; \
	fi; \
	export PATH="$(MOLECULE_PATH)"; \
	$(VENV)/bin/molecule test --scenario-name $(or $(SCENARIO),ubuntu22)

molecule-converge: molecule-env
	@if [ -n "$(EXTRA_CA_BUNDLE)" ] && [ -f $(CA_BUNDLE) ] && [ -s $(CA_BUNDLE) ]; then \
		export SSL_CERT_FILE="$(CURDIR)/$(CA_BUNDLE)" REQUESTS_CA_BUNDLE="$(CURDIR)/$(CA_BUNDLE)"; \
	fi; \
	export PATH="$(MOLECULE_PATH)"; \
	$(VENV)/bin/molecule converge --scenario-name $(or $(SCENARIO),ubuntu22)

molecule-destroy: molecule-env
	@if [ -n "$(EXTRA_CA_BUNDLE)" ] && [ -f $(CA_BUNDLE) ] && [ -s $(CA_BUNDLE) ]; then \
		export SSL_CERT_FILE="$(CURDIR)/$(CA_BUNDLE)" REQUESTS_CA_BUNDLE="$(CURDIR)/$(CA_BUNDLE)"; \
	fi; \
	export PATH="$(MOLECULE_PATH)"; \
	$(VENV)/bin/molecule destroy --scenario-name $(or $(SCENARIO),ubuntu22)
