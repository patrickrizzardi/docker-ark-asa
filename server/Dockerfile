FROM ubuntu:22.04

# Args
ARG BUN_VERSION=1.2.7

# Env variables
ENV USER arkuser
ENV UID 1000
ENV GID 1000
ENV ASA_APPID 2430930
ENV SERVER_SHUTDOWN_TIMEOUT 30
ENV USER_SCRIPTS /home/${USER}/.local/bin

# Steam variables
ENV STEAM_DIR /steam
ENV MANAGER_DIR /manager

# ARK variables
ENV ARK_DIR ${STEAM_DIR}/steamapps/common/asa-server

# Backup variables
ENV BACKUP_PATH /backups
ENV MAX_BACKUPS 10

# Wine variables
ENV STEAM_COMPAT_CLIENT_INSTALL_PATH ${ARK_DIR}
ENV STEAM_COMPAT_DATA_PATH ${STEAM_DIR}/steamapps/compatdata/${ASA_APPID}
ENV WINEDEBUG -all
ENV WINEARCH win64
ENV WINEPREFIX ${STEAM_COMPAT_DATA_PATH}/pfx
ENV DISPLAY :99
# This is required for wine to work and allows us to run this along side bun which is our server manager and entrypoint
ENV XDG_RUNTIME_DIR /tmp
# Add user local bin to PATH for rcon
ENV PATH="${USER_SCRIPTS}:${PATH}"

# Log and pid file locations.
ENV LOG_FILE ${ARK_DIR}/ShooterGame/Saved/Logs/ShooterGame.log
ENV GAME_LOG_FILE ${ARK_DIR}/ShooterGame/Saved/Logs/ServerGame.*.log
ENV API_LOG_FILE ${ARK_DIR}/ShooterGame/Binaries/Win64/logs/ArkApi_*.log
ENV WINE_LOG_FILE ${ARK_DIR}/ShooterGame/Binaries/Win64/logs/wine.log
ENV MONITOR_LOG ${ARK_DIR}/logs/server_monitor.log

# Because steam is a 32 bit app, we need to add the i386 architecture
RUN set -ex; \
    dpkg --add-architecture i386

# Install the required packages
# Start of Selection
RUN set -ex; \
    apt update; \
    apt install -y --no-install-recommends \
    # General utilities
    wget \
    curl \
    jq \
    iproute2 \
    locales \
    procps \
    software-properties-common \
    dbus \
    # Wine dependencies
    lib32gcc-s1 \
    lib32stdc++6 \
    libasound2 \
    libc6-i386 \
    libpulse0 \
    xvfb \
    vim \
    unzip \
    winetricks \
    # Additional dependencies to fix Wine issues
    libgcc-11-dev \
    gcc-multilib \
    g++-multilib \
    libncurses5:i386 \
    libncurses6:i386;
# End of Selection

# Add the winehq repository and install
RUN set -ex; \
    mkdir -pm755 /etc/apt/keyrings; \
    wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key; \
    wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources; \
    apt update; \
    apt install -y --install-recommends winehq-stable

# Set up wine environment properly
RUN set -ex; \
    apt-get -y install cabextract; \
    wget -q -O /usr/bin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks; \
    chmod +x /usr/bin/winetricks;

# Install Cleanup
RUN set -ex; \
    apt-get -y autoremove; \
    apt-get -y clean; \
    rm -rf /var/lib/apt/lists/*; \
    rm -rf /tmp/*; \
    rm -rf /var/tmp/*

# Configure locale for unicode
RUN locale-gen en_US.UTF-8
ENV LANG en_US.UTF-8

# Add the ark user and group that will be used to run the server
RUN set -ex; \
    groupadd --gid ${GID} ${USER}; \
    useradd --create-home --shell /bin/bash --uid ${UID} --gid ${GID} ${USER};

# Create the required directories and set the permissions
RUN set -ex; mkdir -p ${USER_SCRIPTS} ${ARK_DIR} ${MANAGER_DIR} ${STEAM_DIR} ${STEAM_COMPAT_DATA_PATH} ${BACKUP_PATH}
RUN set -ex; mkdir -p ${WINEPREFIX} /tmp/.X11-unix /config
RUN set -ex; chmod 1777 /tmp /tmp/.X11-unix
# Give the user proper permissions for Wine to run
RUN set -ex; touch /etc/fstab
RUN set -ex; chown -R ${USER}:${USER} /home/${USER} ${STEAM_DIR} ${MANAGER_DIR} ${BACKUP_PATH} ${WINEPREFIX} /config
# Ensure log directories exist with correct permissions
RUN set -ex; mkdir -p ${ARK_DIR}/ShooterGame/Saved/Logs ${ARK_DIR}/ShooterGame/Binaries/Win64/logs
RUN set -ex; chown -R ${USER}:${USER} ${ARK_DIR}

# Switch to the ark user so that the server files are owned by the ark user
USER ${USER}

# Add the ll alias. This is just a convenience thing just in case we have an image without it
RUN set -ex; echo "alias ll='ls -alF'" >> /home/${USER}/.bashrc
RUN set -ex; echo "alias bashrc='cat /home/${USER}/.bashrc'" >> /home/${USER}/.bashrc
RUN set -ex; echo "export PATH='$PATH:${USER_SCRIPTS}'" >> /home/${USER}/.bashrc

# Download steamcmd
WORKDIR ${STEAM_DIR}
RUN set -ex; curl "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz" | tar zxvf -

# Switch to the tmp directory to download the server files
WORKDIR /tmp

# Install rcon
RUN set -ex; \
    curl -sSL https://github.com/gorcon/rcon-cli/releases/download/v0.10.3/rcon-0.10.3-amd64_linux.tar.gz > rcon.tar.gz; \
    tar xvf rcon.tar.gz; \
    mv rcon-0.10.3-amd64_linux/rcon ${USER_SCRIPTS}/rcon; \
    rm -rf rcon.tar.gz rcon-0.10.3-amd64_linux; \
    # Add rcon to PATH
    echo 'export PATH="$PATH:${USER_SCRIPTS}"' >> /home/${USER}/.bashrc; \
    chmod +x ${USER_SCRIPTS}/rcon

# Copy scripts to run the server
COPY --chown=${USER} --chmod=755 ./manager ${MANAGER_DIR}

# Copy sample configuration file
COPY --chown=${USER} --chmod=644 ./ark-server-config.json /ark-server-config.json

# Set up the ARK CLI tool
RUN set -ex; \
    ln -sf ${MANAGER_DIR}/ark-cli.sh ${USER_SCRIPTS}/ark; \
    chmod +x ${USER_SCRIPTS}/ark

# Copy the entrypoint script
COPY --chown=${USER} --chmod=755 ./entrypoint.sh /entrypoint.sh

USER ${USER}

WORKDIR ${MANAGER_DIR}
ENTRYPOINT ["/entrypoint.sh"]