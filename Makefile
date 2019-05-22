.PHONY: all
all: checkout up

include .env

-include .make.vars

# Auto-detected variables (computed once and stored until "make clean")
.make.vars: docker-compose.yml Makefile
# Figure out whether we clone over https or git+ssh (you need a GitHub
# account set up with an ssh public key for the latter)
	@echo "# Auto-generated by Makefile, DO NOT EDIT" > $@
	@echo _GITHUB_BASE = $(if $(shell ssh -T git@github.com 2>&1|grep 'successful'),git@github.com:,https://github.com/) >> $@
	@echo _DOCKER_PULLED_IMAGES = $(shell cat docker-compose.yml | grep 'image: ' | grep -v epflidevelop | cut -d: -f2-) >> $@
	@echo _DOCKER_BUILT_IMAGES = epflidevelop/wp-base $(shell cat docker-compose.yml | grep 'image: ' | grep epflidevelop | cut -d: -f2-) >> $@
	@echo _DOCKER_BASE_IMAGE_DEPS = $(shell find wp-ops/docker/wp-base -type f | sed 's/\n/ /g') >> $@
	@echo _DOCKER_MGMT_IMAGE_DEPS = $(shell find wp-ops/docker/mgmt -type f | sed 's/\n/ /g') >> $@
	@echo _DOCKER_HTTPD_IMAGE_DEPS = $(shell find wp-ops/docker/httpd -type f | sed 's/\n/ /g') >> $@


m = $(notdir $(MAKE))
.PHONY: help
help:
	@echo 'Usage:'
	@echo
	@echo '$(m) help           Show this message'
	@echo
	@echo '$(m) up             Start up a local WordPress instance'
	@echo '                    with docker-compose for development.'
	@echo '                    Be sure to review ../README.md for'
	@echo '                    preliminary steps (entry in /etc/hosts,'
	@echo '                    .env file and more)'
	@echo
	@echo '$(m) down           Bring down the development environment'
	@echo '$(m) clean'
	@echo
	@echo '$(m) exec           Enter the management container'
	@echo
	@echo '$(m) httpd          Enter the Apache container'
	@echo
	@echo "$(m) tail-access    Follow the tail of Apache's access resp."
	@echo '$(m) tail-errors    error logs through the terminal'
	@echo
	@echo '$(m) tail-sql       Activate and follow the MySQL general'
	@echo '                    query log'
	@echo
	@echo '$(m) backup         Backup the whole state (incl. MySQL)'
	@echo '                    to wordpress-state.tgz'
	@echo '$(m) restore        Restore from wordpress-state.tgz'

# Default values, can be overridden either on the command line of make
# or in .env
WP_ENV ?= your-env
WP_PORT_HTTP ?= 80
WP_PORT_HTTPS ?= 443

DOCKER_IMAGE_STAMPS = .docker-images-pulled.stamp \
  .docker-base-image-built.stamp \
  .docker-all-images-built.stamp

DOCKER_BASE_IMAGE_NAME = epflidevelop/os-wp-base
DOCKER_HTTPD_IMAGE_NAME = epflidevelop/os-wp-httpd
DOCKER_MGMT_IMAGE_NAME = epflidevelop/os-wp-mgmt

WP_CONTENT_DIR = volumes/wp/wp-content
JAHIA2WP_DIR = volumes/wp/jahia2wp

CTAGS_TARGETS_PYTHON = $(JAHIA2WP_DIR)/src \
  $(JAHIA2WP_DIR)/functional_tests \
  $(JAHIA2WP_DIR)/data

CTAGS_TARGETS_PHP = volumes/wp/*.php \
  volumes/wp/wp-admin \
  volumes/wp/wp-includes \
  $(WP_CONTENT_DIR)/themes/wp-theme-2018 \
  $(WP_CONTENT_DIR)/plugins/epfl-* \
  $(WP_CONTENT_DIR)/plugins/polylang

_mgmt_container = $(shell docker ps -q --filter "label=ch.epfl.wordpress.mgmt.env=$(WP_ENV)")
_httpd_container = $(shell docker ps -q --filter "label=ch.epfl.wordpress.httpd.env=$(WP_ENV)")


.PHONY: vars
vars:
	@echo 'Environment-related vars:'
	@echo '  WP_ENV=$(WP_ENV)'
	@echo '  _mgmt_container=$(_mgmt_container)'
	@echo '  _httpd_container=$(_httpd_container)'
	@echo '  CTAGS_TARGETS=$(CTAGS_TARGETS)'

	@echo ''
	@echo DB-related vars:
	@echo '  MYSQL_ROOT_PASSWORD=$(MYSQL_ROOT_PASSWORD)'
	@echo '  MYSQL_DB_HOST=$(MYSQL_DB_HOST)'
	@echo '  MYSQL_SUPER_USER=$(MYSQL_SUPER_USER)'
	@echo '  MYSQL_SUPER_PASSWORD=$(MYSQL_SUPER_PASSWORD)'

	@echo ''
	@echo 'Wordpress-related vars:'
	@echo '  WP_VERSION=$(WP_VERSION)'
	@echo '  WP_ADMIN_USER=$(WP_ADMIN_USER)'
	@echo '  WP_ADMIN_EMAIL=$(WP_ADMIN_EMAIL)'
	@echo '  WP_PORT_HTTP=$(WP_PORT_HTTP)'
	@echo '  WP_PORT_HTTPS=$(WP_PORT_HTTPS)'

	@echo ''
	@echo 'WPManagement-related vars:'
	@echo '  WP_PORT_PHPMA=$(WP_PORT_PHPMA)'
	@echo '  WP_PORT_SSHD=$(WP_PORT_SSHD)'

######################## Pulling code ##########################
#
# As a matter of taste, we'd rather have Makefile-driven `git clone`s
# than submodules - Plus this lets you substitute your own arrangement
# if you wish.
#
# Code doesn't only get pulled from git either: volumes/wp is extracted
# from the "httpd" Docker image, and we create a couple of symlinks too.

.PHONY: checkout
checkout: \
  $(JAHIA2WP_DIR) \
  $(WP_CONTENT_DIR) \
  $(WP_CONTENT_DIR)/plugins/accred \
  $(WP_CONTENT_DIR)/plugins/tequila \
  $(WP_CONTENT_DIR)/themes/wp-theme-2018 \
  $(WP_CONTENT_DIR)/themes/wp-theme-light \
  wp-ops

git_clone = mkdir -p $(dir $@) || true; cd $(dir $@); test -d $(notdir $@) || git clone $(_GITHUB_BASE)$(strip $(1)) $(notdir $@); touch $(notdir $@)

$(WP_CONTENT_DIR): .docker-all-images-built.stamp $(JAHIA2WP_DIR)
	-rm -f `find $(WP_CONTENT_DIR)/plugins \
	             $(WP_CONTENT_DIR)/themes \
	             $(WP_CONTENT_DIR)/mu-plugins -type l`
	docker run --rm  --name volumes-wp-extractor \
	  --entrypoint /bin/bash \
	  $(DOCKER_HTTPD_IMAGE_NAME) \
	  -c "tar -clf - --exclude=/wp/wp-content/themes/{wp-theme-2018,wp-theme-light} \
	                 --exclude=/wp/wp-content/plugins/{accred,tequila} \
              /wp" \
	  | tar -Cvolumes -xpvf - wp
# Replace excluded directories with a git checkout of same -
# Currently plugins and mu-plugins reside in jahia2wp, for historical
# reasons:
	set -e -x; \
	for linkable in \
	    $(shell cd $(JAHIA2WP_DIR)/data/wp/wp-content; \
	                  find themes plugins -mindepth 1 -maxdepth 1 -type d); \
	do \
	  rm -rf $(WP_CONTENT_DIR)/$$linkable; \
	  ln -s ../../jahia2wp/data/wp/wp-content/$$linkable \
	    $(WP_CONTENT_DIR)/$$linkable; \
	done
	rm -rf $(WP_CONTENT_DIR)/mu-plugins
	ln -s ../jahia2wp/data/wp/wp-content/mu-plugins $(WP_CONTENT_DIR)
	touch $@

$(WP_CONTENT_DIR)/plugins $(WP_CONTENT_DIR)/mu-plugins: $(JAHIA2WP_DIR)
	@mkdir -p $(dir $@) || true
	ln -sf jahia2wp/data/wp/wp-content/$(notdir $@) $@

# For historical reasons, plugins and mu-plugins currently
# reside in a repository called jahia2wp
$(JAHIA2WP_DIR):
	$(call git_clone, epfl-idevelop/jahia2wp)

$(WP_CONTENT_DIR)/plugins/accred: $(WP_CONTENT_DIR)
	$(call git_clone, epfl-sti/wordpress.plugin.accred)
# TODO: unfork!
	(cd $@; git checkout vpsi)

$(WP_CONTENT_DIR)/plugins/tequila: $(WP_CONTENT_DIR)
	$(call git_clone, epfl-sti/wordpress.plugin.tequila)
# TODO: unfork!
	(cd $@; git checkout vpsi)

$(WP_CONTENT_DIR)/themes/wp-theme-2018.git: $(WP_CONTENT_DIR)
	$(call git_clone, epfl-idevelop/wp-theme-2018.git)

$(WP_CONTENT_DIR)/themes/wp-theme-2018: $(WP_CONTENT_DIR)/themes/wp-theme-2018.git
	ln -s wp-theme-2018.git/wp-theme-2018 $@

$(WP_CONTENT_DIR)/themes/wp-theme-light: $(WP_CONTENT_DIR)/themes/wp-theme-2018.git
	ln -s wp-theme-2018.git/wp-theme-light $@

wp-ops:
	$(call git_clone, epfl-idevelop/wp-ops)

################ Building or pulling Docker images ###############

.PHONY: pull
pull:
	rm -f .docker-images-pulled.stamp
	$(MAKE) .docker-images-pulled.stamp

.docker-images-pulled.stamp: docker-compose.yml
	for image in $(_DOCKER_PULLED_IMAGES); do docker pull $$image; done
	touch $@

.docker-base-image-built.stamp: wp-ops 	$(_DOCKER_BASE_IMAGE_DEPS)
	[ -d wp-ops/docker/wp-base ] && \
	  docker build -t $(DOCKER_BASE_IMAGE_NAME) wp-ops/docker/wp-base
	touch $@

.docker-all-images-built.stamp: .docker-base-image-built.stamp wp-ops \
                                 $(_DOCKER_HTTPD_IMAGE_DEPS)
	docker-compose build
	touch $@

.PHONY: docker-build
docker-build:
	rm -f .docker*built.stamp
	$(MAKE) .docker-all-images-built.stamp

.PHONY: clean-images
clean-images:
	for image in $(_DOCKER_PULLED_IMAGES) $(_DOCKER_BUILT_IMAGES) epflidevelop/os-wp-base; do docker rmi $$image || true; done
	rm -f .docker*.stamp


######################## Containers Lifecycle #####################

.PHONY: up
up: checkout $(DOCKER_IMAGE_STAMPS)
	docker-compose up -d

.PHONY: down
down:
	docker-compose down


######################## Development Tasks ########################

.PHONY: exec
exec:
	@docker exec --user www-data -it  \
	  -e WP_ENV=$(WP_ENV) \
	  -e MYSQL_ROOT_PASSWORD=$(MYSQL_ROOT_PASSWORD) \
	  -e MYSQL_DB_HOST=$(MYSQL_DB_HOST) \
	  $(_mgmt_container) bash -l

.PHONY: httpd
httpd:
	@docker exec -it $(_httpd_container) bash -l

.PHONY: tail-errors
tail-errors:
	tail -F volumes/srv/*/logs/error_log.*.`date +%Y%m%d`

.PHONY: tail-access
tail-access:
	tail -F volumes/srv/*/logs/access_log.*.`date +%Y%m%d`

.PHONY: tail-sql
tail-sql:
	./devscripts/mysql-general-log tail

CTAGS_TARGETS = $(CTAGS_TARGETS_PYTHON) $(CTAGS_TARGETS_PHP)
CTAGS_FLAGS = --exclude=node_modules $(EXTRA_CTAGS_FLAGS) -R $(CTAGS_TARGETS)
tags: checkout
	ctags $(CTAGS_FLAGS)

TAGS: checkout
	ctags -e $(CTAGS_FLAGS)

.phony: backup
backup:
	./devscripts/backup-restore backup wordpress-state.tgz

.phony: restore
restore:
	./devscripts/backup-restore restore wordpress-state.tgz

######################## Cleaning up ##########################

.PHONY: clean
clean: down clean-images
	rm -f .make.vars TAGS tags

