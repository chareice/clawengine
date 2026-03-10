.PHONY: setup test server dev-up dev-down db-up db-down db-logs migrate openclaw-up openclaw-down openclaw-logs openclaw-probe

setup:
	mix deps.get

test:
	mix test

server:
	mix run --no-halt

dev-up:
	docker compose up -d postgres openclaw-gateway

dev-down:
	docker compose down

db-up:
	docker compose up -d postgres

db-down:
	docker compose stop postgres

db-logs:
	docker compose logs -f postgres

migrate:
	mix ecto.create
	mix ecto.migrate

openclaw-up:
	docker compose up -d openclaw-gateway

openclaw-down:
	docker compose stop openclaw-gateway

openclaw-logs:
	docker compose logs -f openclaw-gateway

openclaw-probe:
	mix openclaw.probe
