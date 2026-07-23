# Dofus (Unity) dans le navigateur — image applicative.
#
# Base: LinuxServer baseimage-selkies. Elle fournit deja tout l'affichage:
# serveur X, Openbox, Selkies (streaming websocket pixelflux/pcmflux),
# NGINX + HTTP basic auth, PulseAudio, encodage video/audio, persistance /config.
# On se contente d'ajouter les dependances du client natif Dofus 3 + le launcher.
#
# Tag de base epingle (voir README pour changer d'arch/distro).
FROM ghcr.io/linuxserver/baseimage-selkies:ubuntunoble

# Point d'entree de telechargement du launcher Dofus (Linux x86_64). Cette URL
# renvoie un 302 (+ cookie de session) vers l'AppImage courant, actuellement
# "Dofus 3.0-Setup-x86_64.AppImage" ; le nom exact peut changer cote Ankama,
# d'ou l'usage de la redirection plutot que d'un lien direct (qui renvoie 403).
# Surchargez avec --build-arg ANKAMA_APPIMAGE_URL=... si besoin.
ARG ANKAMA_APPIMAGE_URL="https://download.ankama.com/launcher-dofus/full/linux"

ENV DEBIAN_FRONTEND=noninteractive

# Dependances du client natif Dofus 3 (Ankama Launcher = Electron/Chromium ;
# le jeu = Unity/OpenGL/Vulkan). Noms cibles Ubuntu 24.04 "Noble" (transition
# t64). On N'EXECUTE PAS l'AppImage : on extrait son squashfs au build (voir
# plus bas) puis on lance directement le binaire interne. Cela evite FUSE ET
# surtout le "exec format error" du runtime AppImage sous emulation Rosetta
# (Mac Apple Silicon), ou --appimage-extract-and-run echoue aussi.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        # --- Extraction de l'AppImage (sans FUSE ni exec du runtime) ---
        # binutils -> readelf (offset du squashfs) ; squashfs-tools -> unsquashfs.
        binutils \
        squashfs-tools \
        # --- Rendu Unity : Mesa GL + Vulkan (llvmpipe en fallback CPU) ---
        libgl1-mesa-dri \
        libglx-mesa0 \
        libegl-mesa0 \
        mesa-vulkan-drivers \
        libvulkan1 \
        vulkan-tools \
        # --- Encodage/decodage VA-API pour GPU Intel/AMD ---
        mesa-va-drivers \
        # --- Runtime Electron/Chromium du launcher ---
        libnss3 \
        libnspr4 \
        libatk1.0-0t64 \
        libatk-bridge2.0-0t64 \
        libgtk-3-0t64 \
        libgbm1 \
        libasound2t64 \
        libcups2t64 \
        libdrm2 \
        libxshmfence1 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libxrandr2 \
        libxkbcommon0 \
        libpango-1.0-0 \
        libcairo2 \
        # --- Audio (capture PulseAudio deja fournie par la base) ---
        libpulse0 \
        # --- Polices (evite le rendu casse du launcher) ---
        fonts-liberation \
        fonts-noto-core && \
    # Telechargement + extraction du launcher (best-effort ; le script autostart
    # prend aussi en charge un AppImage depose dans /config si celui-ci echoue).
    mkdir -p /opt/ankama && \
    # NB: le WAF Ankama exige un User-Agent "navigateur" contenant AppleWebKit,
    # sinon il renvoie 403 (un simple "Mozilla/5.0 (X11; Linux x86_64)" ne suffit
    # PAS ; "curl/x" non plus).
    ( curl -fSL --retry 3 \
        -A "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36" \
        -b /tmp/ankama-ck -c /tmp/ankama-ck \
        "${ANKAMA_APPIMAGE_URL}" -o /tmp/Ankama-Launcher.AppImage && \
      # Extraction du squashfs SANS executer le runtime AppImage. Un AppImage
      # type-2 = [runtime ELF][squashfs appended] ; le squashfs commence a la fin
      # de la table des sections de l'ELF (e_shoff + e_shnum*e_shentsize). On lit
      # ces champs avec readelf, puis on decompresse avec unsquashfs.
      off="$(readelf -h /tmp/Ankama-Launcher.AppImage | awk '/Start of section headers/{a=$5}/Size of section headers/{b=$5}/Number of section headers/{c=$5}END{print a+b*c}')" && \
      unsquashfs -o "$off" -d /opt/ankama/app -f /tmp/Ankama-Launcher.AppImage && \
      rm -f /tmp/Ankama-Launcher.AppImage ) || \
      echo "AVERTISSEMENT: telechargement/extraction de l'AppImage echoue au build ; deposez-le dans /config/Ankama-Launcher.AppImage" && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# --- Navigateur externe pour le flux de connexion du launcher ---------------
# L'Ankama Launcher delegue certaines etapes de connexion (page d'autorisation
# / 2FA "Connexion securisee") au navigateur SYSTEME via xdg-open (c'est ce
# qu'appelle Electron shell.openExternal). Sans navigateur installe, ces liens
# n'ouvrent rien et la connexion reste bloquee.
#
# On installe Google Chrome (.deb officiel, amd64 uniquement -> coherent avec
# "platform: linux/amd64") : c'est le choix Chrome-family le plus fiable ici.
# Sur Ubuntu 24.04 "Noble", apt "chromium"/"chromium-browser" ne sont que des
# stubs snap (exigent snapd, casses en conteneur), d'ou Chrome plutot que ceux-la.
# La plupart de ses dependances runtime sont deja tirees par le launcher ci-dessus.
#
# PIEGE (verifie) : Chrome DOIT etre lance avec --no-sandbox en conteneur, sinon
# le bac a sable ne s'initialise pas et le process meurt aussitot (rien ne
# s'ouvre). Or Chrome s'auto-enregistre comme handler par defaut de
# x-scheme-handler/https ET pose un .desktop dont l'Exec est
# "/usr/bin/google-chrome-stable %U" (SANS --no-sandbox). xdg-open (xdg-utils
# 1.1.3 de Noble) resout un lien http(s) via ce handler MIME et lance donc Chrome
# SANS --no-sandbox : $BROWSER et l'alternative x-www-browser sont ignores.
# => On force le handler MIME (et les alternatives) vers un wrapper --no-sandbox.
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
        -o /usr/share/keyrings/google-chrome.asc && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.asc] https://dl.google.com/linux/chrome/deb/ stable main" \
        > /etc/apt/sources.list.d/google-chrome.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends google-chrome-stable && \
    # Wrapper : --no-sandbox (le bac a sable ne fonctionne pas en conteneur, comme
    # pour le launcher) + --password-store=basic (pas de gnome-keyring/kwallet ici,
    # evite un blocage au demarrage) + options non-interactives.
    printf '#!/bin/sh\nexec /usr/bin/google-chrome-stable --no-sandbox --no-first-run --no-default-browser-check --password-store=basic "$@"\n' \
        > /usr/local/bin/dofus-browser && \
    chmod +x /usr/local/bin/dofus-browser && \
    # .desktop maison dont l'Exec passe par le wrapper : c'est LUI que xdg-open
    # lancera via le handler MIME (contrairement au .desktop Chrome sans sandbox).
    printf '%s\n' \
        '[Desktop Entry]' \
        'Version=1.0' \
        'Type=Application' \
        'Name=Dofus Browser' \
        'Exec=/usr/local/bin/dofus-browser %U' \
        'Terminal=false' \
        'NoDisplay=true' \
        'MimeType=x-scheme-handler/http;x-scheme-handler/https;text/html;' \
        'Categories=Network;WebBrowser;' \
        > /usr/share/applications/dofus-browser.desktop && \
    # Handler MIME par defaut pour http/https. /etc/xdg est prioritaire sur le
    # /usr/share/applications/mimeapps.list ecrit par Chrome => notre wrapper gagne.
    printf '%s\n' \
        '[Default Applications]' \
        'x-scheme-handler/http=dofus-browser.desktop' \
        'x-scheme-handler/https=dofus-browser.desktop' \
        'text/html=dofus-browser.desktop' \
        > /etc/xdg/mimeapps.list && \
    # Alternatives prioritaires sur Chrome (priorite 200) pour les chemins qui
    # passent par x-www-browser / gnome-www-browser / sensible-browser.
    update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/local/bin/dofus-browser 300 && \
    update-alternatives --install /usr/bin/gnome-www-browser gnome-www-browser /usr/local/bin/dofus-browser 300 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# xdg-open et Electron (shell.openExternal) : $BROWSER en dernier recours ; le
# handler MIME ci-dessus reste la voie principale de resolution.
ENV BROWSER=/usr/local/bin/dofus-browser

# Scripts et defaults (autostart) injectes par la couche s6 de la base.
COPY /root /

# Ports internes servis par le NGINX de la base (proxifie aussi le websocket
# de donnees 8082). Exposes au reverse proxy uniquement, pas publiquement.
EXPOSE 3000 3001
