.PHONY: setup test server openclaw-up openclaw-down openclaw-logs openclaw-probe

setup:
	mix deps.get

test:
	mix test

server:
	mix run --no-halt

openclaw-up:
	docker compose up -d openclaw-gateway

openclaw-down:
	docker compose down

openclaw-logs:
	docker compose logs -f openclaw-gateway

openclaw-probe:
	mix openclaw.probe
