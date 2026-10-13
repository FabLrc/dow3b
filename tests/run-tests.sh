#!/usr/bin/env bash
# Tests de la stack Dofus — AUCUN build d'image ni lancement du conteneur.
#
# 4 niveaux (chacun SKIP proprement si ses outils manquent) :
#   A. Coherence des fichiers (zero dependance).
#   B. Config compose RESOLUE (docker compose + python3) : durcissement, ports...
#   C. Linters (shellcheck / hadolint / yamllint).
#   D. Comportement du script autostart sur de faux AppImages
#      (mksquashfs + unsquashfs + readelf).
#
# Sortie : PASS / FAIL / SKIP. Code retour != 0 si au moins un FAIL.
# Compatible bash 3.2 (macOS) : pas de tableaux associatifs.

# Idiome volontaire : "condition; check $? 'description'".
# shellcheck disable=SC2319
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

PASS=0; FAIL=0; SKIP=0
C_G=$'\033[32m'; C_R=$'\033[31m'; C_Y=$'\033[33m'; C_0=$'\033[0m'
ok(){ printf '  %sPASS%s %s\n' "$C_G" "$C_0" "$1"; PASS=$((PASS+1)); }
no(){ printf '  %sFAIL%s %s\n' "$C_R" "$C_0" "$1"; FAIL=$((FAIL+1)); }
sk(){ printf '  %sSKIP%s %s\n' "$C_Y" "$C_0" "$1"; SKIP=$((SKIP+1)); }
section(){ printf '\n== %s ==\n' "$1"; }
# check <condition-status> <description> : PASS si la commande precedente a reussi.
check(){ if [ "$1" -eq 0 ]; then ok "$2"; else no "$2"; fi; }
has_cmds(){ for c in "$@"; do command -v "$c" >/dev/null 2>&1 || return 1; done; }

# ============================================================
section "A. Coherence des fichiers"
# Ordre s6 : la resynchro de l'autostart doit passer apres la copie initiale de
# la base (init-selkies-config) et avant le lancement d'Openbox (svc-de) ;
# sans ces fichiers, elle tourne en parallele (course) ou pas du tout.
S6=root/etc/s6-overlay/s6-rc.d
for f in "$S6/init-dofus-autostart/dependencies.d/init-selkies-config" \
         "$S6/svc-de/dependencies.d/init-dofus-autostart" \
         "$S6/user/contents.d/init-dofus-autostart"; do
  [ -f "$f" ]; check $? "s6 : $f"
done
[ -x "$S6/init-dofus-autostart/run" ] && [ -x root/defaults/autostart ]
check $? "scripts executables (autostart, init-dofus-autostart/run)"

grep -qxF '.env' .gitignore; check $? ".gitignore : .env (secrets) ignore"

# Toute variable REQUISE (${VAR:?...}) doit etre documentee dans .env.example.
req_vars=$(grep -ohE '\$\{[A-Z_][A-Z0-9_]*:\?' docker-compose*.yml \
           | sed -E 's/\$\{([A-Z_][A-Z0-9_]*):\?/\1/' | sort -u)
for v in $req_vars; do
  grep -Eq "^$v=" .env.example; check $? ".env.example documente la requise $v"
done
# Toute variable referencee doit avoir un defaut (:-) OU etre documentee.
all_vars=$(grep -ohE '\$\{[A-Z_][A-Z0-9_]*' docker-compose*.yml | sed -E 's/\$\{//' | sort -u)
for v in $all_vars; do
  { grep -Eq "\\\$\{$v:-" docker-compose*.yml || grep -Eq "^$v=" .env.example; }
  check $? "variable $v : defaut ou documentee"
done

# DRINODE / DRI_NODE definis (meme vides) desactivent la detection AUTO_GPU de la base.
! grep -vhE '^[[:space:]]*#' docker-compose*.yml | grep -Eq 'DRI_?NODE'
check $? "compose : DRINODE/DRI_NODE non forces (detection AUTO_GPU preservee)"

# ============================================================
section "B. Config compose resolue (sans build)"
if has_cmds docker python3 && docker compose version >/dev/null 2>&1; then
  tmpenv="$(mktemp)"
  printf 'CUSTOM_USER=test\nPASSWORD=testpassword\nDOMAIN=dofus.example.com\n' > "$tmpenv"
  for files in "docker-compose.yml" \
               "docker-compose.yml docker-compose.gpu-dri.yml" \
               "docker-compose.yml docker-compose.gpu-nvidia.yml"; do
    args=(); for f in $files; do args+=(-f "$f"); done
    if ! json="$(docker compose --env-file "$tmpenv" "${args[@]}" config --format json 2>&1)"; then
      no "[$files] config invalide : $json"
      continue
    fi
    ok "[$files] config valide"
    # Chaque ligne "FAIL <msg>" / "PASS <msg>" emise par python devient une assertion.
    while IFS= read -r line; do
      case "$line" in
        PASS\ *) ok "[$files] ${line#PASS }" ;;
        *)       no "[$files] ${line#FAIL }" ;;
      esac
    done < <(printf '%s' "$json" | python3 -c '
import json, sys
cfg = json.load(sys.stdin)
svc = cfg["services"]
dofus, caddy = svc.get("dofus", {}), svc.get("caddy", {})
env = dofus.get("environment") or {}
def check(cond, msg): print(("PASS " if cond else "FAIL ") + msg)
for k, v in [("DISABLE_SUDO", "true"), ("DISABLE_TERMINALS", "true"),
             ("SELKIES_FILE_TRANSFERS", ""), ("SELKIES_COMMAND_ENABLED", "false"),
             ("SELKIES_PRINTING_ENABLED", "false")]:
    check(env.get(k) == v, "durcissement %s=%r (vu : %r)" % (k, v, env.get(k)))
# HARDEN_DESKTOP desactive xdg-open => casse la connexion Ankama (page 2FA).
check(str(env.get("HARDEN_DESKTOP", "")).lower() != "true", "pas de HARDEN_DESKTOP (casse la connexion Ankama)")
# Le watchdog RESTART_APP relance le launcher quand il se ferme (crash, auto-update).
check(env.get("RESTART_APP") == "true", "RESTART_APP=true (relance du launcher)")
check(not dofus.get("ports"), "dofus ne publie aucun port (reverse proxy uniquement)")
check(any(v.get("target") == "/config" for v in dofus.get("volumes", [])), "dofus : /config persistant")
check(int(dofus.get("shm_size") or 0) >= 1 << 30, "dofus : shm_size >= 1 Go (Unity/Electron)")
check(any(str(p.get("target")) == "443" for p in caddy.get("ports", [])), "caddy publie 443")
')
  done
  rm -f "$tmpenv"
else
  sk "docker compose / python3 absents — config resolue non verifiee"
fi

# ============================================================
section "C. Linters"
if has_cmds shellcheck; then
  shellcheck -x root/defaults/autostart "$S6"/init-dofus-autostart/run tests/run-tests.sh >/dev/null 2>&1
  check $? "shellcheck (autostart, s6, tests)"
else sk "shellcheck absent"; fi

if has_cmds hadolint; then
  hadolint Dockerfile >/dev/null 2>&1; check $? "hadolint Dockerfile"
else sk "hadolint absent"; fi

if has_cmds yamllint; then
  yamllint -d relaxed docker-compose*.yml .github/workflows/*.yml >/dev/null 2>&1
  check $? "yamllint (compose, CI)"
else sk "yamllint absent"; fi

# ============================================================
section "D. Comportement du script autostart"
# On execute le VRAI script avec sh (dash en CI : detecte les bashismes), ses
# chemins /config et /opt redriges vers un dossier temporaire. Faux AppImage =
# [ELF quelconque][squashfs contenant un AppRun qui journalise son lancement].
ELF=/bin/true
if has_cmds mksquashfs unsquashfs readelf && readelf -h "$ELF" >/dev/null 2>&1; then
  T="$(mktemp -d)"
  LOG="$T/log"
  mkdir -p "$T/bin" "$T/config" "$T/src"
  printf '#!/bin/sh\necho "XMESSAGE $*" >> "%s"\n' "$LOG" > "$T/bin/xmessage"
  chmod +x "$T/bin/xmessage"
  mk_apprun(){ # <dir> <tag>
    mkdir -p "$1"
    # shellcheck disable=SC2016 # $APPDIR & co. doivent s'expandre dans le faux AppRun, pas ici.
    printf '#!/bin/sh\necho "RUN %s APPDIR=$APPDIR APPIMAGE=$APPIMAGE $*" >> "%s"\n' "$2" "$LOG" > "$1/AppRun"
    # Parent du launcher : doit rester le script autostart (watchdog RESTART_APP).
    # shellcheck disable=SC2016
    printf '[ -r /proc/$PPID/cmdline ] && echo "PARENT $(tr "\\0" " " < /proc/$PPID/cmdline)" >> "%s"\n' "$LOG" >> "$1/AppRun"
    chmod +x "$1/AppRun"
  }
  mk_apprun "$T/baked" BAKED
  mk_apprun "$T/src/app" UPDATED
  mksquashfs "$T/src/app" "$T/src/sq" -quiet -noappend >/dev/null
  cat "$ELF" "$T/src/sq" > "$T/src/new.AppImage"
  sed -e "s#\"/config/#\"$T/config/#g" -e "s#\"/opt/ankama/app\"#\"$T/baked\"#g" \
      root/defaults/autostart > "$T/autostart"
  P="$T/config/Ankama-Launcher.AppImage"
  CACHE="$T/config/.ankama-app"

  if [ "$(grep -c "$T" "$T/autostart")" -lt 3 ]; then
    no "autostart : chemins non redirigeables (constantes renommees ?) — scenarios ignores"
  else
    # run_autostart : lance le script, attend les xmessage en arriere-plan.
    run_autostart(){ : > "$LOG"; PATH="$T/bin:$PATH" sh "$T/autostart" >/dev/null 2>&1; sleep 0.3; }
    logged(){ grep -qF -- "$1" "$LOG"; }

    run_autostart
    logged "RUN BAKED APPDIR=$T/baked APPIMAGE=$P --no-sandbox"
    check $? "image seule : lance le launcher embarque, APPIMAGE persistant, --no-sandbox"
    if [ -d /proc/self ]; then
      logged "PARENT sh $T/autostart"
      check $? "le launcher reste enfant du script autostart (pas d'exec : watchdog RESTART_APP)"
    else sk "/proc absent — parente du launcher non verifiee"; fi
    [ -f "$P" ] && [ ! -s "$P" ]; check $? "image seule : cible d'auto-update vide creee dans /config"

    # Auto-update (electron-updater) : supprime $APPIMAGE puis y ecrit la nouvelle version.
    rm -f "$P"; cp "$T/src/new.AppImage" "$P"
    run_autostart
    logged "RUN UPDATED APPDIR=$CACHE APPIMAGE=$P"; check $? "apres auto-update : version extraite lancee"

    before="$(ls -lid "$CACHE")"; sleep 1
    run_autostart
    [ "$(ls -lid "$CACHE")" = "$before" ] && logged "RUN UPDATED"
    check $? "relance : cache reutilise sans reextraction"

    sleep 1; head -c 4096 "$T/src/new.AppImage" > "$P"     # AppImage tronque
    run_autostart
    logged "RUN BAKED" && logged "XMESSAGE -center Extraction de $P impossible"
    check $? "AppImage corrompu : secours sur le launcher embarque + message"
    [ -x "$CACHE/AppRun" ] && [ ! -e "$CACHE.tmp" ]
    check $? "AppImage corrompu : cache precedent intact, pas de residu"

    rm -rf "$T/baked"
    run_autostart
    logged "XMESSAGE -center Extraction de $P impossible" && ! logged "RUN "
    check $? "AppImage corrompu sans launcher embarque : message d'erreur, rien lance"

    rm -f "$P"
    run_autostart
    logged "XMESSAGE -center Ankama Launcher introuvable"
    check $? "aucun launcher : message 'introuvable'"
  fi
  rm -rf "$T"
else
  sk "mksquashfs/unsquashfs/readelf absents — comportement autostart non teste"
fi

# ============================================================
printf '\n----------------------------------------\n'
printf '%sPASS %d%s  %sFAIL %d%s  %sSKIP %d%s\n' \
  "$C_G" "$PASS" "$C_0" "$C_R" "$FAIL" "$C_0" "$C_Y" "$SKIP" "$C_0"
[ "$FAIL" -eq 0 ] || exit 1
