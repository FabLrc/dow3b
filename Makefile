.PHONY: test build up up-dri up-nvidia down logs

# Tests statiques (aucun build ni lancement du conteneur).
test:
	./tests/run-tests.sh

# Build + demarrage (rendu logiciel, portable partout).
build:
	docker compose build

up:
	docker compose up -d --build

# Demarrage avec GPU.
up-dri:
	docker compose -f docker-compose.yml -f docker-compose.gpu-dri.yml up -d --build

up-nvidia:
	docker compose -f docker-compose.yml -f docker-compose.gpu-nvidia.yml up -d --build

down:
	docker compose down

logs:
	docker compose logs -f dofus
