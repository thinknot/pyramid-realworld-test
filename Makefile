# Convenience makefile to build the dev env and run common commands
# Based on https://github.com/teamniteo/Makefile

.PHONY: all
all: .installed

.PHONY: install
install:
	@rm -f .installed  # force re-install
	@make .installed

.installed: pyproject.toml poetry.lock
	@echo "pyproject.toml or poetry.lock are newer than .installed, (re)installing in 1 second"
	@sleep 1
	@poetry check
	@poetry install
	@poetry run pre-commit install -f --hook-type pre-commit
	@poetry run pre-commit install -f --hook-type pre-push
	@echo "This file is used by 'make' for keeping track of last install time. If pyproject.toml or poetry.lock are newer then this file (.installed) then all 'make *' commands that depend on '.installed' know they need to run 'poetry install' first." \
		> .installed

# Start database in docker in foreground
.PHONY: pgsql
pgsql: .installed
	@docker stop pgsql || true
	@docker rm pgsql || true
	@docker run -it --rm --name pgsql -v $(shell pwd)/.docker:/docker-entrypoint-initdb.d -p 5432:5432 postgres:11.2-alpine \
		postgres -c 'log_statement=all' -c 'max_connections=1000' -c 'log_connections=true'  -c 'log_disconnections=true'  -c 'log_duration=true'

# Start database in docker in background
.PHONY: start-pgsql
start-pgsql: .installed
	@docker start pgsql || docker run -d -v $(shell pwd)/.docker:/docker-entrypoint-initdb.d -p 5432:5432 --name pgsql postgres:11.2-alpine

# Open devdb with pgweb, a fantastic browser-based postgres browser
.PHONY: pgweb
pgweb:
	@docker run -p 8081:8081 --rm -it --link pgsql:pgsql -e "DATABASE_URL=postgres://conduit_dev:@pgsql:5432/conduit_dev?sslmode=disable" sosedoff/pgweb

# Open devdb with pgcli, a fantastic cli-based postgres browser (https://www.pgcli.com/)
.PHONY: pgcli
pgcli:
	@docker run --rm -it --link pgsql:pgsql dencold/pgcli "postgres://conduit_dev:@pgsql:5432/conduit_dev?sslmode=disable"

.PHONY: clean-pgsql
clean-pgsql: .installed
	@docker stop pgsql || true
	@docker rm pgsql || true

.PHONY: stop-pgsql
stop-pgsql: .installed
	@docker stop pgsql || true

# Drop, recreate and populate development database with demo content
.PHONY: devdb
devdb: .installed
	@CHECK_DB_MIGRATED=0 poetry run python -m conduit.scripts.drop_tables
	@poetry run alembic -c etc/alembic.ini -x ini=etc/development.ini upgrade head
	@poetry run python -m conduit.scripts.populate

.PHONY: pshell
pshell: .installed
	@poetry run pshell etc/development.ini

# Run development server
.PHONY: run
run: .installed
	@ENABLE_ENDPOINT_VALIDATION=1 poetry run pserve etc/development.ini --reload

# Testing and linting targets
all = false

# Testing and linting targets
.PHONY: lint
lint: .installed
# 1. get all unstaged modified files
# 2. get all staged modified files
# 3. get all untracked files
# 4. run pre-commit checks on them
ifeq ($(all),true)
	@poetry run pre-commit run --hook-stage push --all-files
else
	@{ git diff --name-only ./; git diff --name-only --staged ./;git ls-files --other --exclude-standard; } \
		| sort -u | uniq | xargs poetry run pre-commit run --hook-stage push --files
endif

.PHONY: types
types: .installed
	@poetry run mypy src/conduit
	@cat ./typecov/linecount.txt
	@poetry run typecov 100 ./typecov/linecount.txt

# anything, in regex-speak
filter = "."

# additional arguments for pytest
unit_test_all = "false"
ifeq ($(filter),".")
	unit_test_all = "true"
endif
ifdef path
	unit_test_all = "false"
endif
args = ""
pytest_args = -k $(filter) $(args)
coverage_args = ""
ifeq ($(unit_test_all),"true")
	coverage_args = --cov=conduit --cov-branch --cov-report html --cov-report xml:cov.xml --cov-report term-missing --cov-fail-under=100
endif

.PHONY: unit
unit: .installed
ifeq ($(unit_test_all),"true")
	@poetry run python -m conduit.scripts.drop_tables -c etc/test.ini
endif
ifndef path
	@poetry run pytest src/conduit $(coverage_args) $(pytest_args)
else
	@poetry run pytest $(path)
endif

.PHONY: postman-tests
postman-tests: .installed
	# Your need to install newman (npm install newman)
	# and run `make run` in a another tab
	@APIURL=http://localhost:8080/api src/conduit/tests/postman/run-postman-tests.sh


.PHONY: tests
tests: lint types unit

.PHONY: clean
clean:
	@rm -rf .venv/ .coverage .mypy_cache htmlcov/ htmltypecov \
		src/conduit.egg-info typecov xunit.xml \
		.git/hooks/pre-commit .git/hooks/pre-push
	@rm -f .installed
