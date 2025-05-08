FROM ubuntu:22.04

# Args and environment variables - grouped by purpose
ARG BUN_VERSION=1.2.7

# System and user configuration
ENV USER arkuser
ENV UID 1000
ENV GID 1000
ENV USER_SCRIPTS /home/${USER}/.local/bin
ENV PATH="${USER_SCRIPTS}:${PATH}"

# Game and server variables
ENV ASA_APPID 2430930
ENV SERVER_SHUTDOWN_TIMEOUT 30
ENV STEAM_DIR /steam
ENV ARK_SAVE_DIR /ark
ENV MANAGER_DIR /manager
ENV BACKUP_PATH /backups
ENV MAX_BACKUPS 10

# Wine configuration
ENV STEAM_COMPAT_CLIENT_INSTALL_PATH ${ARK_SAVE_DIR}
ENV STEAM_COMPAT_DATA_PATH ${ARK_SAVE_DIR}/steamapps/compatdata/${ASA_APPID}
ENV WINEDEBUG -all
ENV WINEARCH win64
ENV WINEPREFIX ${STEAM_COMPAT_DATA_PATH}/pfx
ENV DISPLAY :99
ENV XDG_RUNTIME_DIR /tmp

# Log and pid file locations
ENV LOG_FILE ${ARK_SAVE_DIR}/ShooterGame/Saved/Logs/ShooterGame.log
ENV CRASH_LOG_FILE ${ARK_SAVE_DIR}/ShooterGame/Saved/Logs/Crash*.log
ENV GAME_LOG_FILE ${ARK_SAVE_DIR}/ShooterGame/Saved/Logs/ServerGame.*.log
ENV API_LOG_FILE ${ARK_SAVE_DIR}/ShooterGame/Binaries/Win64/logs/ArkApi_*.log
ENV WINE_LOG_FILE ${ARK_SAVE_DIR}/ShooterGame/Binaries/Win64/logs/wine.log
ENV MONITOR_LOG ${ARK_SAVE_DIR}/logs/server_monitor.log

# Locale configuration
ENV LANG en_US.UTF-8

# Add i386 architecture for Steam (32-bit app)
RUN dpkg --add-architecture i386

# Install all required packages in a single layer
RUN set -ex \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
    # General utilities
    wget curl jq iproute2 locales procps software-properties-common \
    dbus htop vim unzip \
    # Wine dependencies
    lib32gcc-s1 lib32stdc++6 libasound2 libc6-i386 libpulse0 xvfb \
    winetricks libgcc-11-dev gcc-multilib g++-multilib libncurses5:i386 \
    libncurses6:i386 cabextract \
    # Add WineHQ repository and install
    && mkdir -pm755 /etc/apt/keyrings \
    && wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key \
    && wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources \
    && apt-get update \
    && apt-get install -y --install-recommends winehq-stable \
    # Configure winetricks
    && wget -q -O /usr/bin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks \
    && chmod +x /usr/bin/winetricks \
    # Configure locale
    && locale-gen en_US.UTF-8 \
    # Cleanup to reduce image size
    && apt-get -y autoremove \
    && apt-get -y clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Create user and setup directory structure in a single layer
RUN set -ex \
    # Create user and group
    && groupadd --gid ${GID} ${USER} \
    && useradd --create-home --shell /bin/bash --uid ${UID} --gid ${GID} ${USER} \
    # Create required directories
    && mkdir -p ${USER_SCRIPTS} ${ARK_SAVE_DIR} ${MANAGER_DIR} ${STEAM_DIR} \
    ${STEAM_COMPAT_DATA_PATH} ${BACKUP_PATH} ${WINEPREFIX} /tmp/.X11-unix \
    # Set permissions
    && chmod 1777 /tmp /tmp/.X11-unix \
    && touch /etc/fstab \
    && chown -R ${USER}:${USER} /home/${USER} ${STEAM_DIR} ${MANAGER_DIR} \
    ${BACKUP_PATH} ${WINEPREFIX} ${ARK_SAVE_DIR}

# Switch to non-root user for remaining operations
USER ${USER}

# Set up user environment
RUN set -ex \
    # Configure shell aliases and environment
    && echo "alias ll='ls -alF'" >> /home/${USER}/.bashrc \
    && echo "alias bashrc='cat /home/${USER}/.bashrc'" >> /home/${USER}/.bashrc \
    && echo "export PATH='$PATH:${USER_SCRIPTS}'" >> /home/${USER}/.bashrc \
    # Download SteamCMD
    && cd ${STEAM_DIR} \
    && curl "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf - \
    # Install RCON
    && cd /tmp \
    && curl -sSL https://github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-amd64_linux.tar.gz > rcon.tar.gz \
    && tar xvf rcon.tar.gz \
    && mv rcon-0.10.3-amd64_linux/rcon ${USER_SCRIPTS}/rcon \
    && rm -rf rcon.tar.gz rcon-0.10.3-amd64_linux \
    && chmod +x ${USER_SCRIPTS}/rcon

# Copy scripts and configurations (separated for better cache utilization)
COPY --chown=${USER} --chmod=644 ./config ${ARK_SAVE_DIR}/ShooterGame/Saved/Config/WindowsServer
COPY --chown=${USER} --chmod=755 ./manager ${MANAGER_DIR}
COPY --chown=${USER} --chmod=755 ./entrypoint.sh /entrypoint.sh

# Set up ARK CLI tool
RUN ln -sf ${MANAGER_DIR}/ark-cli.sh ${USER_SCRIPTS}/ark \
    && chmod +x ${USER_SCRIPTS}/ark

WORKDIR ${ARK_SAVE_DIR}
ENTRYPOINT ["/entrypoint.sh"]