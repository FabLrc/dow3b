# dow3b — Dofus (Unity) dans le navigateur

Jouer à **Dofus 3 (Unity)** depuis un simple navigateur, le jeu tournant dans un
conteneur Docker. Aucune installation côté client hormis un navigateur.

Le conteneur lance l'**Ankama Launcher** (client Linux natif) et diffuse son
affichage via **Selkies** (streaming websocket). **Caddy** ajoute le HTTPS.
Tout passe en TCP sur le port 443 — pas de WebRTC/UDP, pas de TURN.

## Prérequis

- Docker + Docker Compose v2.
- ~20 Go de disque libre (jeu ~16 Go + image).
- GPU **recommandé** (jeu Unity) : NVIDIA (`nvidia-container-toolkit`) ou
  Intel/AMD (`/dev/dri`). Sans GPU : rendu logiciel, FPS réduits.

## Démarrage

```bash
cp .env.example .env      # renseigner CUSTOM_USER, PASSWORD, DOMAIN
make up                   # sans GPU (portable)
```

Avec GPU : `make up-dri` (Intel/AMD) ou `make up-nvidia`.

Puis ouvrir `https://<DOMAIN>`, s'authentifier (CUSTOM_USER / PASSWORD) →
l'Ankama Launcher s'affiche.

## Première utilisation

Se connecter avec **son compte Ankama** → laisser télécharger Dofus (~16 Go,
une fois) → **Jouer**. Session et jeu persistent dans le volume `/config` :
pas de re-téléchargement ni de re-login après un redémarrage.

## Accès

`DOMAIN` dans `.env` :
- **LAN / local** : `dofus.local` (ou une IP) + décommenter `tls internal` dans
  le `Caddyfile` (certificat auto-signé).
- **Distant** : domaine public pointant vers l'hôte, ports 80/443 ouverts →
  certificat Let's Encrypt automatique.

Protégé par HTTP basic auth par-dessus HTTPS → utiliser un mot de passe fort.

## Commandes

```bash
make test        # tests statiques (sans build ni lancement)
make up          # build + démarre (rendu logiciel)
make up-dri      # + GPU Intel/AMD
make up-nvidia   # + GPU NVIDIA
make logs        # logs du conteneur
make down        # arrête
```

`make test` tourne aussi en CI ([.github/workflows/ci.yml](.github/workflows/ci.yml))
à chaque push/PR, sans build de l'image.

## Notes

- Si le build échoue au téléchargement du launcher (URL Ankama changée) :
  `docker compose build --build-arg ANKAMA_APPIMAGE_URL="<url>"`, ou déposer
  l'AppImage dans le volume sous `/config/Ankama-Launcher.AppImage`.
- Écran noir / lib manquante : `make logs`, puis compléter le `Dockerfile`
  (paquets ciblant Ubuntu 24.04 « Noble »).
- Usage personnel, **votre** compte Ankama — respecter les CGU d'Ankama.
