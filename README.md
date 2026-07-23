# dow3b — Dofus (Unity) dans le navigateur

Jouer à **Dofus 3 (Unity)** depuis un simple navigateur web, le jeu tournant
dans un conteneur Docker. Objectif : portabilité — aucune installation côté
client hormis un navigateur.

Le conteneur lance l'**Ankama Launcher** (client Linux natif, plus besoin de
Wine depuis Dofus 3) et diffuse son affichage via **Selkies** (streaming
websocket, base [LinuxServer](https://github.com/linuxserver/docker-baseimage-selkies)).
Un reverse proxy **Caddy** ajoute HTTPS pour l'accès distant.

## Architecture

```
Navigateur ──HTTPS/443──> Caddy ──HTTP/3000──> Conteneur "dofus"
                                                 ├─ NGINX (basic auth)
                                                 ├─ Selkies (streaming websocket)
                                                 ├─ Openbox + serveur X
                                                 └─ Ankama Launcher ─> Dofus (Unity)
```

Tout le flux vidéo/audio passe en **TCP/websocket sur le port 443** : pas de
WebRTC, pas d'UDP, **pas de serveur TURN** à gérer.

## Prérequis hôte

- Docker + Docker Compose v2.
- **GPU (recommandé pour la fluidité)** — Dofus est un jeu Unity :
  - NVIDIA : pilote + [`nvidia-container-toolkit`](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).
  - Intel/AMD : pilotes Mesa à jour (accès `/dev/dri`).
  - Sans GPU : fonctionne en rendu logiciel (llvmpipe), mais FPS réduits.
- ~20 Go d'espace disque libre (jeu ~16 Go + image).

## Démarrage rapide

```bash
cp .env.example .env
# Editez .env : CUSTOM_USER, PASSWORD, DOMAIN (voir "Accès" plus bas).

# Sans GPU (portable, rendu logiciel) :
docker compose up -d --build
```

Puis ouvrez `https://<DOMAIN>` dans un navigateur, authentifiez-vous
(CUSTOM_USER / PASSWORD), et l'Ankama Launcher s'affiche.

### Avec GPU

```bash
# Intel / AMD (VA-API via /dev/dri)
docker compose -f docker-compose.yml -f docker-compose.gpu-dri.yml up -d --build

# NVIDIA (NVENC via nvidia-container-toolkit)
docker compose -f docker-compose.yml -f docker-compose.gpu-nvidia.yml up -d --build
```

Pour Intel/AMD, renseignez les GID `render`/`video` de votre hôte dans `.env`
(`getent group render video`) si le passthrough échoue.

## Première utilisation

1. Sur le launcher affiché dans le navigateur, connectez-vous avec **votre
   compte Ankama**.
2. Laissez le launcher **télécharger Dofus** (~16 Go, une seule fois — persisté
   dans le volume `dofus-data`).
3. Cliquez sur **Jouer**.

Session Ankama et jeu sont conservés dans le volume `/config` : après un
redémarrage du conteneur, pas de re-téléchargement ni de re-login.

> L'AppImage du launcher est téléchargée au build. Si l'URL Ankama a changé et
> que le build échoue, surchargez-la :
> `--build-arg ANKAMA_APPIMAGE_URL="<nouvelle-url>"`, ou déposez manuellement le
> fichier dans le volume sous `/config/Ankama-Launcher.AppImage`.

## Accès

- **Local / LAN** : mettez `DOMAIN=dofus.local` (ou une IP) dans `.env` et
  décommentez `tls internal` dans le `Caddyfile` (certificat auto-signé à
  accepter dans le navigateur).
- **Distant (Internet)** : `DOMAIN` = un domaine public pointant vers l'hôte,
  ports 80/443 ouverts → Caddy obtient un certificat Let's Encrypt automatique.

L'accès est protégé par HTTP basic auth (`CUSTOM_USER`/`PASSWORD`) **par-dessus**
HTTPS. Utilisez un mot de passe fort.

## Tests (sans build ni lancement)

Une suite de tests **statiques** valide la configuration sans construire l'image
ni lancer le jeu :

```bash
make test        # ou : ./tests/run-tests.sh
```

- **Niveau A** — assertions statiques (présence/contenu des fichiers, autostart
  exécutable + bons flags, cohérence Dockerfile, parité `${VAR}` ↔ `.env.example`,
  `.gitignore` protège `.env`…). Zéro dépendance.
- **Niveau B** — `docker compose config` sur la base + chaque override GPU :
  valide et fusionne le YAML **sans build ni pull** (exécuté si Docker est présent).
- **Niveau C** — `shellcheck` / `hadolint` / `yamllint` si installés, sinon SKIP.

Code retour ≠ 0 si un test échoue → intégrable en CI.

## Dépannage

- **Écran noir / launcher absent** : consultez `docker compose logs -f dofus`.
  Un `xmessage` s'affiche si l'AppImage est introuvable.
- **Lib manquante au lancement du launcher** : ajoutez le paquet manquant au
  `Dockerfile` (les noms ciblent Ubuntu 24.04 « Noble »).
- **FPS faibles** : vous êtes probablement en rendu logiciel — activez un
  override GPU. Selkies affiche des stats de flux dans l'UI web.
- **Le launcher ne démarre pas (sandbox)** : déjà lancé avec `--no-sandbox` et
  `--appimage-extract-and-run` (pas de FUSE requis).

## Fichiers

| Fichier | Rôle |
|---|---|
| `Dockerfile` | Image applicative (baseimage-selkies + deps Dofus + launcher). |
| `root/defaults/autostart` | Lance l'Ankama Launcher dans la session. |
| `docker-compose.yml` | Stack de base (dofus + caddy), rendu logiciel. |
| `docker-compose.gpu-dri.yml` | Override GPU Intel/AMD. |
| `docker-compose.gpu-nvidia.yml` | Override GPU NVIDIA. |
| `Caddyfile` | Reverse proxy HTTPS. |
| `.env.example` | Modèle de configuration. |
| `tests/run-tests.sh` | Tests statiques (sans build ni lancement). |
| `Makefile` | Raccourcis : `make test`, `make up`, `make up-dri`, `make up-nvidia`. |

## Notes

- Usage personnel : c'est **votre** compte Ankama. Respectez les CGU d'Ankama.
- v1 = **une** session/instance. Le multi-compte (multiboxing) est une évolution
  future (compter ~2 Go de RAM par instance).
