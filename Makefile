.PHONY: all
all: checkout up

include .env

-include .make.vars

# Auto-detected variables (computed once and stored until "make clean")
.make.vars: docker-compose.yml Makefile
	@echo "# Auto-generated by Makefile, DO NOT EDIT" > $@
# Figure out whether we clone over https or git+ssh (you need a GitHub
# account set up with an ssh public key for the latter)
	@echo _GITHUB_BASE = $(if $(shell ssh -T git@github.com 2>&1|grep 'successful'),git@github.com:,https://github.com/) >> $@
	@echo _DOCKER_PULLED_IMAGES = $(shell cat docker-compose.yml | grep 'image: ' | grep -v epflsi | cut -d: -f2-) >> $@
	@echo _DOCKER_BUILT_IMAGES = epflsi/wp-base $(shell cat docker-compose.yml | grep 'image: ' | grep epflsi | cut -d: -f2-) >> $@
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

DOCKER_BASE_IMAGE_NAME = epflsi/os-wp-base
DOCKER_HTTPD_IMAGE_NAME = epflsi/os-wp-httpd
DOCKER_MGMT_IMAGE_NAME = epflsi/os-wp-mgmt

WP_CONTENT_DIR = volumes/wp/5/wp-content
WP4_CONTENT_DIR = volumes/wp/4/wp-content
JAHIA2WP_DIR = volumes/wp/jahia2wp
WP_CLI_DIR = volumes/wp/wp-cli/vendor/epfl-si/wp-cli

CTAGS_TARGETS_PYTHON = $(JAHIA2WP_DIR)/src \
  $(JAHIA2WP_DIR)/functional_tests \
  $(JAHIA2WP_DIR)/data

CTAGS_TARGETS_PHP = volumes/wp/5/*.php \
  volumes/wp/5/wp-admin \
  volumes/wp/5/wp-includes \
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
  $(WP_CONTENT_DIR)/plugins/enlighter \
  $(WP_CONTENT_DIR)/plugins/epfl-menus \
  $(WP_CONTENT_DIR)/themes/wp-theme-2018 \
  $(WP_CONTENT_DIR)/themes/wp-theme-light \
  $(WP_CONTENT_DIR)/plugins/wp-gutenberg-epfl \
  $(WP_CONTENT_DIR)/plugins/epfl-404 \
  $(WP_CONTENT_DIR)/plugins/EPFL-settings \
  $(WP_CONTENT_DIR)/plugins/epfl-scienceqa \
  $(WP_CONTENT_DIR)/plugins/EPFL-Content-Filter \
  $(WP_CONTENT_DIR)/plugins/epfl-intranet \
  $(WP_CONTENT_DIR)/plugins/epfl-restauration \
  $(WP_CONTENT_DIR)/plugins/EPFL-Library-Plugins \
  $(WP4_CONTENT_DIR)/plugins/accred \
  $(WP4_CONTENT_DIR)/plugins/tequila \
  $(WP4_CONTENT_DIR)/themes/wp-theme-2018 \
  $(WP4_CONTENT_DIR)/themes/wp-theme-light \
  $(WP_CLI_DIR) \
  wp-ops \
  volumes/usrlocalbin

git_clone = mkdir -p $(dir $@) || true; devscripts/ensure-git-clone.sh $(_GITHUB_BASE)$(strip $(1)) $@; touch $@

ifeq ($(shell uname -s),Linux)
_HOST_TAR_X := tar -m --overwrite
else
_HOST_TAR_X := tar
endif

volumes/usrlocalbin: .docker-all-images-built.stamp
	mkdir $@ || true
	docker run --rm  --name volumes-usrlocalbin-extractor \
	  --entrypoint /bin/bash \
	  $(DOCKER_MGMT_IMAGE_NAME) \
	  -c "tar -C/usr/local/bin --exclude=new-wp-site -clf - ." \
	  | $(_HOST_TAR_X) -Cvolumes/usrlocalbin -xpvf -
	rm -f volumes/usrlocalbin/new-wp-site
	ln -s /wp-ops/docker/mgmt/new-wp-site.sh volumes/usrlocalbin/new-wp-site
	touch $@

$(WP_CONTENT_DIR) $(WP4_CONTENT_DIR): .docker-all-images-built.stamp $(JAHIA2WP_DIR)
	-rm -f `find $(WP_CONTENT_DIR)/plugins \
	             $(WP_CONTENT_DIR)/themes \
	             $(WP_CONTENT_DIR)/mu-plugins -type l`
	docker run --rm  --name volumes-wp-extractor \
	  --entrypoint /bin/bash \
	  $(DOCKER_HTTPD_IMAGE_NAME) \
	  -c "tar -clf - --exclude=/wp/*/wp-content/themes/{wp-theme-2018,wp-theme-light} \
	                 --exclude=/wp/*/wp-content/plugins/{accred,tequila,enlighter,wp-gutenberg-epfl,epfl*,EPFL*} \
              /wp" \
	  | $(_HOST_TAR_X) -Cvolumes -xpvf - wp
# Excluded directories are replaced with a git checkout of same.
# Currently a number of plugins and mu-plugins reside in jahia2wp, for
# historical reasons:
	set -e -x; \
	for linkable in \
	    $(shell cd $(JAHIA2WP_DIR)/data/wp/wp-content; \
	                  find themes plugins -mindepth 1 -maxdepth 1 -type d \
                    -not -name epfl-menus \
                    -not -name epfl-404 \
                    -not -name EPFL-settings \
                    -not -name epfl-scienceqa \
                    -not -name EPFL-Content-Filter \
                    -not -name epfl-intranet \
                    -not -name epfl-restauration \
                    -not -name EPFL-Library-Plugins \
                    ); \
	do \
	  rm -rf $(WP_CONTENT_DIR)/$$linkable $(WP4_CONTENT_DIR)/$$linkable; \
	  ln -s ../../../jahia2wp/data/wp/wp-content/$$linkable \
	    $(WP_CONTENT_DIR)/$$linkable; \
	  ln -s ../../../jahia2wp/data/wp/wp-content/$$linkable \
	    $(WP4_CONTENT_DIR)/$$linkable; \
	done
	rm -rf $(WP_CONTENT_DIR)/mu-plugins $(WP4_CONTENT_DIR)/mu-plugins
	ln -s ../../jahia2wp/data/wp/wp-content/mu-plugins $(WP_CONTENT_DIR)
	ln -s ../../jahia2wp/data/wp/wp-content/mu-plugins $(WP4_CONTENT_DIR)
	touch $@

$(WP_CONTENT_DIR)/plugins $(WP_CONTENT_DIR)/mu-plugins: $(JAHIA2WP_DIR)
	@mkdir -p $(dir $@) || true
	ln -sf jahia2wp/data/wp/wp-content/$(notdir $@) $@

# For historical reasons, plugins and mu-plugins currently
# reside in a repository called jahia2wp
$(JAHIA2WP_DIR):
	$(call git_clone, epfl-si/jahia2wp)
	(cd $@; git checkout release2018)

$(WP_CONTENT_DIR)/plugins/accred: $(WP_CONTENT_DIR)
	$(call git_clone, epfl-sti/wordpress.plugin.accred)
# TODO: unfork!
	(cd $@; git checkout vpsi)

$(WP_CONTENT_DIR)/plugins/tequila: $(WP_CONTENT_DIR)
	$(call git_clone, epfl-sti/wordpress.plugin.tequila)
# TODO: unfork!
	(cd $@; git checkout vpsi)

$(WP_CONTENT_DIR)/plugins/wp-gutenberg-epfl: $(WP_CONTENT_DIR)
	$(call git_clone, epfl-si/wp-gutenberg-epfl)

$(WP_CONTENT_DIR)/themes/wp-theme-2018.git: $(WP_CONTENT_DIR)
	$(call git_clone, epfl-si/wp-theme-2018.git)

$(WP_CONTENT_DIR)/themes/wp-theme-2018: $(WP_CONTENT_DIR)/themes/wp-theme-2018.git
	ln -sf wp-theme-2018.git/wp-theme-2018 $@

$(WP_CONTENT_DIR)/themes/wp-theme-light: $(WP_CONTENT_DIR)/themes/wp-theme-2018.git
	ln -sf wp-theme-2018.git/wp-theme-light $@

$(WP_CONTENT_DIR)/plugins/epfl-menus: $(WP_CONTENT_DIR)
	$(call git_clone, epfl-si/wp-plugin-epfl-menus)

$(WP_CONTENT_DIR)/plugins/epfl-404: $(WP_CONTENT_DIR)
	$(call git_clone, epfl-si/wp-plugin-epfl-404)

$(WP_CONTENT_DIR)/plugins/EPFL-settings: $(WP_CONTENT_DIR)
	$(call git_clone, epfl-si/wp-plugin-epfl-settings)

$(WP_CONTENT_DIR)/plugins/epfl-scienceqa: $(WP_CONTENT_DIR)
	$(call git_clone, epfl-si/wp-plugin-epfl-scienceqa)

$(WP_CONTENT_DIR)/plugins/EPFL-Content-Filter: $(WP_CONTENT_DIR)
	$(call git_clone, epfl-si/wp-plugin-epfl-content-filter)

$(WP_CONTENT_DIR)/plugins/epfl-intranet: $(WP_CONTENT_DIR)
	$(call git_clone, epfl-si/wp-plugin-epfl-intranet)

$(WP_CONTENT_DIR)/plugins/epfl-restauration: $(WP_CONTENT_DIR)
	$(call git_clone, epfl-si/wp-plugin-epfl-restauration)

$(WP_CONTENT_DIR)/plugins/EPFL-Library-Plugins: $(WP_CONTENT_DIR)
	$(call git_clone, epfl-si/wp-plugin-epfl-library)

$(WP_CONTENT_DIR)/plugins/enlighter: $(WP_CONTENT_DIR)
	$(call git_clone, epfl-si/enlighter)

$(WP_CLI_DIR):
	$(call git_clone, epfl-si/wp-cli)

wp-ops:
	$(call git_clone, epfl-si/wp-ops)
	$(MAKE) -C wp-ops checkout

############ Additional symlinks for obsolete WordPress 4 codebase ###########
$(WP4_CONTENT_DIR)/plugins/%: $(WP4_CONTENT_DIR)
	@-mkdir -p $(dir $@) 2>/dev/null
	ln -sf ../../../5/wp-content/plugins/$* $@

$(WP4_CONTENT_DIR)/themes/%: $(WP4_CONTENT_DIR)
	@-mkdir -p $(dir $@) 2>/dev/null
	ln -sf ../../../5/wp-content/themes/$* $@

################ Building or pulling Docker images ###############

.PHONY: pull
pull:
	rm -f .docker-images-pulled.stamp
	$(MAKE) .docker-images-pulled.stamp

.docker-images-pulled.stamp: docker-compose.yml
	for image in $(_DOCKER_PULLED_IMAGES); do docker pull $$image; done
	touch $@

ifdef OUTSIDE_EPFL
_OUTSIDE_EPFL_DOCKER_BUILD_ARGS:=--build-arg INSTALL_AUTO_FLAGS=--exclude=wp-media-folder
endif

.docker-base-image-built.stamp: wp-ops 	$(_DOCKER_BASE_IMAGE_DEPS)
	[ -d wp-ops/docker/wp-base ] && \
	  docker build -t $(DOCKER_BASE_IMAGE_NAME) $(DOCKER_BASE_BUILD_ARGS) $(_OUTSIDE_EPFL_DOCKER_BUILD_ARGS) wp-ops/docker/wp-base
	touch $@

.docker-all-images-built.stamp: .docker-base-image-built.stamp wp-ops \
                                 $(_DOCKER_HTTPD_IMAGE_DEPS)
	docker-compose build $(DOCKER_BUILD_ARGS)
	touch $@

.PHONY: docker-build
docker-build:
	rm -f .docker*built.stamp
	$(MAKE) .docker-all-images-built.stamp DOCKER_BUILD_ARGS=$(DOCKER_BUILD_ARGS) DOCKER_BASE_BUILD_ARGS=$(DOCKER_BASE_BUILD_ARGS)

.PHONY: clean-images
clean-images:
	for image in $(_DOCKER_PULLED_IMAGES) $(_DOCKER_BUILT_IMAGES) epflsi/os-wp-base; do docker rmi $$image || true; done
	docker image prune
	rm -f .docker*.stamp


######################## Development Lifecycle #####################

SITE_DIR := /srv/test/wp-httpd/htdocs
.PHONY: wp5
# TODO: We currently don't have a story to create a site at the top
# level automatically.
wp5: checkout
	[ -L volumes/$(SITE_DIR)/wp ] || ln -sf /wp/5 volumes/$(SITE_DIR)/wp
	[ -L volumes/$(SITE_DIR)/wp-content/plugins/wp-gutenberg-epfl ] || ln -sf ../../wp/wp-content/plugins/wp-gutenberg-epfl volumes/$(SITE_DIR)/wp-content/plugins/
	docker exec -it $(_httpd_container) bash -c 'cd $(SITE_DIR); wp --allow-root plugin deactivate epfl' || true
	docker exec -it $(_httpd_container) bash -c 'cd $(SITE_DIR); wp --allow-root plugin activate wp-gutenberg-epfl'

.PHONY: up
up: checkout $(DOCKER_IMAGE_STAMPS)
	docker-compose up -d
	(cd $(WP_CONTENT_DIR)/plugins/wp-gutenberg-epfl; npm i; npm start)

.PHONY: down
down:
	docker-compose down

_find_git_depots := find . -name .git -prune |xargs -n 1 dirname
.PHONY: gitstatus
gitstatus:
	for dir in `$(_find_git_depots)`; do (set -e -x; cd $$dir; git status); done

gitpull:
	for dir in `$(_find_git_depots)`; do (set -e -x; cd $$dir; git pull); done

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

.PHONY: mrproper
mrproper: clean
	rm -rf volumes/wp
