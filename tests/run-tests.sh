#!/usr/bin/env bash
# Tests statiques de la stack Dofus — AUCUN build ni lancement du conteneur.
#
# 3 niveaux :
#   A. Assertions statiques (toujours, zero dependance).
#   B. Validation compose (si `docker` present) : parse/merge, pas de build/pull.
#   C. Linters (shellcheck / hadolint / yamllint) : uniquement si installes.
#
# Sortie : PASS / FAIL / SKIP. Code retour != 0 si au moins un FAIL.
# Compatible bash 3.2 (macOS) : pas de tableaux associatifs.

set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"

PASS=0; FAIL=0; SKIP=0
C_G=$'\033[32m'; C_R=$'\033[31m'; C_Y=$'\033[33m'; C_0=$'\033[0m'
ok(){ printf '  %sPASS%s %s\n' "$C_G" "$C_0" "$1"; PASS=$((PASS+1)); }
no(){ printf '  %sFAIL%s %s\n' "$C_R" "$C_0" "$1"; FAIL=$((FAIL+1)); }
sk(){ printf '  %sSKIP%s %s\n' "$C_Y" "$C_0" "$1"; SKIP=$((SKIP+1)); }
section(){ printf '\n== %s ==\n' "$1"; }

# --- helpers d'assertion ---
has_file(){ [ -f "$1" ] && ok "fichier present : $1" || no "fichier manquant : $1"; }
is_exec(){ [ -x "$1" ] && ok "executable : $1" || no "non executable : $1"; }
# contains <fichier> <regex-ERE> <description>
contains(){ if grep -Eq -- "$2" "$1" 2>/dev/null; then ok "$3"; else no "$3 (motif absent : $2 dans $1)"; fi; }

# ============================================================
section "A. Presence des fichiers"
for f in Dockerfile docker-compose.yml docker-compose.gpu-dri.yml \
         docker-compose.gpu-nvidia.yml Caddyfile .env.example .gitignore \
         README.md root/defaults/autostart; do
  has_file "$f"
done

# ============================================================
section "A. Script autostart"
is_exec root/defaults/autostart
contains root/defaults/autostart '^#!/bin/sh'                  "autostart : shebang sh (POSIX, pas de bashismes)"
contains root/defaults/autostart 'AppRun'                      "autostart : lance l'AppRun extrait (pas le runtime AppImage)"
contains root/defaults/autostart '--no-sandbox'               "autostart : Chromium sans sandbox"
contains root/defaults/autostart '/config/Ankama-Launcher\.AppImage' "autostart : fallback AppImage persistant"
contains root/defaults/autostart '/opt/ankama/app'            "autostart : AppDir embarquee (extraite au build)"
# Ne doit PAS reintroduire l'exec direct de l'AppImage : casse sous Rosetta (Mac ARM).
# (On ignore les commentaires : le "pourquoi" mentionne le flag a titre explicatif.)
if grep -vE '^[[:space:]]*#' root/defaults/autostart | grep -Eq -- '--appimage-extract-and-run'; then
  no "autostart : ne doit pas executer le runtime AppImage (echec 'exec format error' sous Rosetta)"
else
  ok "autostart : n'execute pas le runtime AppImage"
fi

# ============================================================
section "A. Dockerfile"
contains Dockerfile 'FROM ghcr\.io/linuxserver/baseimage-selkies' "Dockerfile : base selkies epinglee"
contains Dockerfile 'ARG ANKAMA_APPIMAGE_URL'                     "Dockerfile : URL launcher en build-arg"
contains Dockerfile '^COPY /root /'                               "Dockerfile : injection des defaults"
contains Dockerfile 'EXPOSE 3000 3001'                            "Dockerfile : ports internes exposes"
contains Dockerfile 'mesa-vulkan-drivers'                         "Dockerfile : rendu Vulkan (Unity)"
contains Dockerfile 'libgtk-3-0t64'                               "Dockerfile : runtime GTK/Electron (Noble t64)"
contains Dockerfile 'libnss3'                                     "Dockerfile : runtime Chromium"
contains Dockerfile 'squashfs-tools'                              "Dockerfile : unsquashfs (extraction AppImage)"
contains Dockerfile 'unsquashfs'                                  "Dockerfile : extraction du squashfs au build"

# ============================================================
section "A. docker-compose (base)"
contains docker-compose.yml '^[[:space:]]*dofus:'          "compose : service dofus"
contains docker-compose.yml '^[[:space:]]*caddy:'          "compose : service caddy"
contains docker-compose.yml 'dofus-data:/config'  "compose : volume persistant /config"
contains docker-compose.yml 'shm_size'            "compose : /dev/shm dimensionne"
contains docker-compose.yml '"443:443"'           "compose : caddy publie 443"
# Le port du conteneur dofus ne doit PAS etre publie en clair (expose only).
if grep -Eq '^[[:space:]]*ports:' docker-compose.yml && \
   awk '/dofus:/{f=1} /caddy:/{f=0} f&&/ports:/{print}' docker-compose.yml | grep -q .; then
  no "compose : le service dofus ne doit pas publier de port (reverse proxy uniquement)"
else
  ok "compose : dofus n'expose pas de port en clair"
fi

# ============================================================
section "A. Overrides GPU"
contains docker-compose.gpu-dri.yml '/dev/dri:/dev/dri' "override dri : passthrough /dev/dri"
contains docker-compose.gpu-dri.yml 'DRINODE'           "override dri : noeud de rendu"
contains docker-compose.gpu-nvidia.yml 'driver: nvidia' "override nvidia : reservation GPU"
contains docker-compose.gpu-nvidia.yml 'NVIDIA_DRIVER_CAPABILITIES' "override nvidia : capabilities"

# ============================================================
section "A. Caddyfile"
contains Caddyfile 'reverse_proxy dofus:3000' "caddy : proxy vers le conteneur"
contains Caddyfile '\{\$DOMAIN\}'             "caddy : domaine depuis l'environnement"

# ============================================================
section "A. .gitignore protege les secrets"
contains .gitignore '^\.env$' ".gitignore : .env ignore"

# ============================================================
section "A. Parite variables compose <-> .env.example"
# Toute variable REQUISE (\${VAR:?...}) doit etre documentee dans .env.example.
req_vars=$(grep -ohE '\$\{[A-Z_][A-Z0-9_]*:\?' docker-compose*.yml 2>/dev/null \
           | sed -E 's/\$\{([A-Z_][A-Z0-9_]*):\?/\1/' | sort -u)
for v in $req_vars; do
  if grep -Eq "^$v=" .env.example; then ok ".env.example documente la requise $v"
  else no ".env.example : variable requise $v absente"; fi
done
# Toute variable referencee doit avoir un defaut (:-) OU etre documentee.
all_vars=$(grep -ohE '\$\{[A-Z_][A-Z0-9_]*' docker-compose*.yml 2>/dev/null \
           | sed -E 's/\$\{//' | sort -u)
for v in $all_vars; do
  if grep -Eq "\\\$\{$v:-" docker-compose*.yml || grep -Eq "^$v=" .env.example; then
    ok "variable $v : defaut ou documentee"
  else
    no "variable $v : ni defaut (:-) ni entree .env.example"
  fi
done

# ============================================================
section "B. Validation docker compose (parse/merge, sans build)"
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  tmpenv="$(mktemp)"
  cat > "$tmpenv" <<'EOF'
CUSTOM_USER=test
PASSWORD=testpassword
DOMAIN=dofus.example.com
EOF
  run_cfg(){ # <desc> <fichiers...>
    local desc="$1"; shift
    local args=(); for f in "$@"; do args+=(-f "$f"); done
    if docker compose --env-file "$tmpenv" "${args[@]}" config -q >/dev/null 2>&1; then
      ok "$desc"
    else
      no "$desc (voir : docker compose ${args[*]} config)"
    fi
  }
  run_cfg "compose base valide"        docker-compose.yml
  run_cfg "compose + override dri"     docker-compose.yml docker-compose.gpu-dri.yml
  run_cfg "compose + override nvidia"  docker-compose.yml docker-compose.gpu-nvidia.yml
  rm -f "$tmpenv"
else
  sk "docker/compose absent — validation compose ignoree"
fi

# ============================================================
section "C. Linters optionnels"
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -x root/defaults/autostart >/dev/null 2>&1; then ok "shellcheck autostart"
  else no "shellcheck autostart (shellcheck root/defaults/autostart)"; fi
else sk "shellcheck absent"; fi

if command -v hadolint >/dev/null 2>&1; then
  if hadolint Dockerfile >/dev/null 2>&1; then ok "hadolint Dockerfile"
  else no "hadolint Dockerfile (hadolint Dockerfile)"; fi
else sk "hadolint absent"; fi

if command -v yamllint >/dev/null 2>&1; then
  if yamllint -d relaxed docker-compose*.yml >/dev/null 2>&1; then ok "yamllint compose"
  else no "yamllint compose (yamllint docker-compose*.yml)"; fi
else sk "yamllint absent"; fi

# ============================================================
printf '\n----------------------------------------\n'
printf '%sPASS %d%s  %sFAIL %d%s  %sSKIP %d%s\n' \
  "$C_G" "$PASS" "$C_0" "$C_R" "$FAIL" "$C_0" "$C_Y" "$SKIP" "$C_0"
[ "$FAIL" -eq 0 ] || exit 1
