# Dofus (Unity) dans le navigateur — image applicative.
#
# Base: LinuxServer baseimage-selkies. Elle fournit deja tout l'affichage:
# serveur X, Openbox, Selkies (streaming websocket pixelflux/pcmflux),
# NGINX + HTTP basic auth, PulseAudio, encodage video/audio, persistance /config.
# On se contente d'ajouter les dependances du client natif Dofus 3 + le launcher.
#
# Tag de base epingle (voir README pour changer d'arch/distro).
FROM ghcr.io/linuxserver/baseimage-selkies:ubuntunoble

# URL de l'AppImage de l'Ankama Launcher. Peut changer cote Ankama : surchargez
# avec --build-arg ANKAMA_APPIMAGE_URL=... si le telechargement echoue.
ARG ANKAMA_APPIMAGE_URL="https://launcher.cdn.ankama.com/installers/production/Ankama%20Launcher-x86_64.AppImage"

ENV DEBIAN_FRONTEND=noninteractive

# Dependances du client natif Dofus 3 (Ankama Launcher = Electron/Chromium ;
# le jeu = Unity/OpenGL/Vulkan). Noms cibles Ubuntu 24.04 "Noble" (transition
# t64). On lance l'AppImage via --appimage-extract-and-run => pas besoin de FUSE.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
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
    # Telechargement du launcher (best-effort ; le script autostart prend aussi
    # en charge un AppImage depose dans /config si celui-ci echoue).
    mkdir -p /opt/ankama && \
    ( curl -fSL "${ANKAMA_APPIMAGE_URL}" -o /opt/ankama/Ankama-Launcher.AppImage && \
      chmod +x /opt/ankama/Ankama-Launcher.AppImage ) || \
      echo "AVERTISSEMENT: telechargement de l'AppImage echoue au build ; deposez-le dans /config/Ankama-Launcher.AppImage" && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Scripts et defaults (autostart) injectes par la couche s6 de la base.
COPY /root /

# Ports internes servis par le NGINX de la base (proxifie aussi le websocket
# de donnees 8082). Exposes au reverse proxy uniquement, pas publiquement.
EXPOSE 3000 3001
