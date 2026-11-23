ifeq ($(wildcard .env),)
$(error Missing .env; create it from .env.example with: cp .env.example .env)
endif

include .env
# Versions fixades de les ISO (fitxer versionat, sintaxi compatible Make/Bash)
include configs/versions.env

export PROJECT_ROOT ARTIFACTS_DIR CONFIGS_DIR SSH_PUBLIC_KEY_DIR SSH_PRIVATE_KEY_DIR
export ROUTEROS_VERSION ROUTEROS_VDI_FILENAME ROUTEROS_VDI_PATH ROUTEROS_BOX_NAME ROUTEROS_BOX_FILE
export VBOX_ROOT_GROUP VM_ROUTERS_GROUP VM_TEMPLATES_GROUP VBOXMANAGE_BIN
export DEBIAN_VERSION DEBIAN_ISO_FILENAME DEBIAN_ISO_URL DEBIAN_ISO_MIRROR_URL DEBIAN_ISO_SHA256
export PVE_VERSION PVE_ISO_FILENAME PVE_ISO_URL PVE_ISO_MIRROR_URL PVE_ISO_SHA256
export ISO_DIR BUILD_DIR VM_SERVERS_GROUP VM_PRINTERS_GROUP VM_DESKTOPS_GROUP VCORP_DOMAIN
export PVE_MEMORY PVE_CPUS PVE_DISK_MB SYSADMIN_PASSWORD PVE_ROOT_PASSWORD

BASH_DIR := $(PROJECT_ROOT)/infrastructure/bash
BOOTSTRAP_DIR := $(PROJECT_ROOT)/automation/scripts/bootstrap

.PHONY: help deploy-routers delete-routers reset-routers reset_routers ssh-keys routeros-box
.PHONY: check_host download_isos create_templates delete_templates

help:
	@printf '%s\n' \
	  'Targets:' \
	  '  deploy-routers  Create and configure the router VMs' \
	  '  delete-routers  Delete the router VM group' \
	  '  reset-routers   Delete and redeploy the router VMs' \
	  '  ssh-keys        Generate the project SSH keys' \
	  '  routeros-box    Build the RouterOS Vagrant box' \
	  '' \
	  'Activitat 2:' \
	  '  check_host        Comprova VT-x, RAM, disc i eines de l'"'"'amfitrió' \
	  '  download_isos     Descarrega i verifica (SHA256) les ISO fixades' \
	  '  create_templates  Crea els templates Debian Server i Desktop (FORCE=1 per refer-los)' \
	  '  delete_templates  Esborra els templates (falla si tenen clons enllaçats)'

deploy-routers:
	"$(BASH_DIR)/deploy_routers.sh"

delete-routers:
	"$(BASH_DIR)/del_vbox_group.sh" --routers

reset-routers:
	"$(BASH_DIR)/del_vbox_group.sh" --routers
	"$(BASH_DIR)/deploy_routers.sh"

# Keep the original target name available for existing callers.
reset_routers: reset-routers

ssh-keys:
	"$(BOOTSTRAP_DIR)/create_ssh_keys.sh"

routeros-box:
	"$(BOOTSTRAP_DIR)/create_mikrotik_box.sh"

# ------------------------------------------------------------
# Activitat 2
# ------------------------------------------------------------

check_host:
	"$(BASH_DIR)/check_host.sh"

download_isos:
	"$(BASH_DIR)/download_isos.sh"

create_templates: download_isos
	FORCE="$(FORCE)" "$(BASH_DIR)/create_templates.sh"

delete_templates:
	"$(BASH_DIR)/del_vbox_group.sh" "$(VM_TEMPLATES_GROUP)"
