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
Le bureau est durci (`docker-compose.yml`) : pas de `sudo` ni de terminal,
pas de transfert de fichiers ni de commandes depuis le client web.
`HARDEN_DESKTOP` n'est volontairement pas utilisé : il désactive `xdg-open`,
indispensable à la connexion Ankama.

## Commandes

```bash
make test        # tests statiques (sans build ni lancement)
make up          # build + démarre (rendu logiciel)
make up-dri      # + GPU Intel/AMD
make up-nvidia   # + GPU NVIDIA
make update-launcher  # rebuild en retéléchargeant le launcher Ankama
make logs        # logs du conteneur
make down        # arrête
```

La CI ([.github/workflows/ci.yml](.github/workflows/ci.yml)) lance `make test` puis
construit l'image (sans la publier) à chaque push/PR et chaque lundi, pour
repérer une URL Ankama ou une image de base cassée.

## Notes

- Le launcher est téléchargé au build ; un échec fait échouer le build. Si l'URL
  Ankama a changé : `docker compose build --build-arg ANKAMA_APPIMAGE_URL="<url>"`.
  Pour s'en passer : `--build-arg ANKAMA_APPIMAGE_URL=` (vide) puis déposer
  l'AppImage dans le volume sous `/config/Ankama-Launcher.AppImage`.
- Le cache Docker conserve le launcher du premier build : `make update-launcher`
  force son retéléchargement (seule cette couche est reconstruite).
- Le launcher se met à jour tout seul : la nouvelle version est écrite dans
  `/config/Ankama-Launcher.AppImage` (un fichier vide y est créé d'office) puis
  extraite au lancement suivant. Pour revenir au launcher de l'image, supprimer
  ce fichier.
- Écran noir / lib manquante : `make logs`, puis compléter le `Dockerfile`
  (paquets ciblant Ubuntu 26.04 « Resolute »).
- Le script de lancement (`autostart`) est géré par l'image : il est
  resynchronisé dans `/config` à chaque démarrage, toute modification manuelle
  y est écrasée.
- Usage personnel, **votre** compte Ankama — respecter les CGU d'Ankama.
