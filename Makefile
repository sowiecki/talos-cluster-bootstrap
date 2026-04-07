# Configuration – change these to match your environment
TERRAFORM_DIR   ?= terraform
PROXMOX_HOST    ?= 192.168.1.65
PROXMOX_USER    ?= root
SSH_KEY_PATH    ?= $(HOME)/.ssh/proxmox-k3s
TF_VAR_proxmox_api_token ?= $(shell cat .proxmox-token 2>/dev/null)

# Tool versions (optional pinning)
KUBECTL_VERSION ?= $(shell curl -L -s https://dl.k8s.io/release/stable.txt)

# Phony targets
.PHONY: check-tools install-tools create-token init apply bootstrap verify destroy clean

# Default target
bootstrap: check-tools install-tools create-token init apply verify
	@echo "✅ Bootstrap complete! kubeconfig is at $(PWD)/kubeconfig"

# ----------------------------------------------------------------------
# Tool installation (same as before)
# ----------------------------------------------------------------------
check-tools:
	@which tofu >/dev/null 2>&1 || (echo "OpenTofu not found. Run 'make install-tools' to install." && exit 1)
	@which talosctl >/dev/null 2>&1 || (echo "talosctl not found. Run 'make install-tools' to install." && exit 1)
	@which kubectl >/dev/null 2>&1 || (echo "kubectl not found. Run 'make install-tools' to install." && exit 1)
	@which helm >/dev/null 2>&1 || (echo "helm not found. Run 'make install-tools' to install." && exit 1)
	@which git >/dev/null 2>&1 || (echo "git not found. Run 'make install-tools' to install." && exit 1)

install-tools:
	@echo "📦 Installing required tools..."
	# OpenTofu
	@if ! which tofu >/dev/null 2>&1; then \
		curl -fsSL https://get.opentofu.org/install-opentofu.sh | sudo bash; \
	fi
	# talosctl
	@if ! which talosctl >/dev/null 2>&1; then \
		curl -sL https://talos.dev/install | sh; \
	fi
	# kubectl
	@if ! which kubectl >/dev/null 2>&1; then \
		curl -LO "https://dl.k8s.io/release/$(KUBECTL_VERSION)/bin/linux/amd64/kubectl" && \
		chmod +x kubectl && sudo mv kubectl /usr/local/bin/; \
	fi
	# helm
	@if ! which helm >/dev/null 2>&1; then \
		curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
		chmod 700 get_helm.sh && ./get_helm.sh && rm get_helm.sh; \
	fi
	# git (if missing)
	@if ! which git >/dev/null 2>&1; then \
		sudo apt update && sudo apt install -y git; \
	fi

# ----------------------------------------------------------------------
# Proxmox API token creation (if not already set)
# Uses SSH with explicit key, no agent required
# ----------------------------------------------------------------------
create-token:
	@if [ -z "$(TF_VAR_proxmox_api_token)" ]; then \
		echo "🔑 No API token found. Creating one via SSH..."; \
		ssh -i $(SSH_KEY_PATH) -o BatchMode=yes -o ConnectTimeout=5 $(PROXMOX_USER)@$(PROXMOX_HOST) "exit" 2>/dev/null || \
		(echo "❌ Cannot connect to Proxmox host. Check SSH key and host." && exit 1); \
		token=$$(ssh -i $(SSH_KEY_PATH) $(PROXMOX_USER)@$(PROXMOX_HOST) \
			"pveum user add terraform@pve 2>/dev/null || true; \
			 pveum role add TerraformRole -privs \"VM.Allocate VM.Audit VM.Clone VM.Config.CDROM VM.Config.Cloudinit VM.Config.CPU VM.Config.Disk VM.Config.HWType VM.Config.Memory VM.Config.Network VM.Config.Options VM.Monitor VM.PowerMgmt Datastore.AllocateSpace Datastore.AllocateTemplate\" 2>/dev/null || true; \
			 pveum acl modify / -user terraform@pve -role TerraformRole 2>/dev/null || true; \
			 pveum user token add terraform@pve provider --privsep=0 | grep -oP 'full-tokenid: \K.*'"); \
		if [ -n "$$token" ]; then \
			echo "$$token" > .proxmox-token; \
			echo "✅ Token saved to .proxmox-token"; \
		else \
			echo "❌ Failed to create token. Please create it manually and set TF_VAR_proxmox_api_token."; \
			exit 1; \
		fi \
	fi

# ----------------------------------------------------------------------
# OpenTofu steps
# ----------------------------------------------------------------------
init:
	@echo "🔄 Initializing OpenTofu..."
	cd $(TERRAFORM_DIR) && tofu init

apply:
	@echo "🚀 Applying Terraform configuration..."
	@cd $(TERRAFORM_DIR) && TF_VAR_proxmox_api_token="$(TF_VAR_proxmox_api_token)" tofu apply -auto-approve
apply:
	@echo "🚀 Applying Terraform configuration..."
	cd $(TERRAFORM_DIR) && tofu apply -auto-approve

# ----------------------------------------------------------------------
# Verification
# ----------------------------------------------------------------------
verify:
	@echo "🔍 Verifying cluster..."
	@if [ -f kubeconfig ]; then \
		KUBECONFIG=kubeconfig kubectl get nodes || \
		(echo "⏳ Waiting for nodes to be ready..." && sleep 30 && KUBECONFIG=kubeconfig kubectl get nodes); \
	else \
		echo "kubeconfig not found. Cluster might not be ready."; \
	fi

# ----------------------------------------------------------------------
# Clean up
# ----------------------------------------------------------------------
destroy:
	@echo "💥 Destroying cluster..."
	cd $(TERRAFORM_DIR) && tofu destroy -auto-approve

clean: destroy
	@rm -f kubeconfig talosconfig .proxmox-token
	@echo "🧹 Cleaned up local files."