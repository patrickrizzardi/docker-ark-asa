FROM ubuntu:22.04

# Args
ARG BUN_VERSION=1.2.7

# Env variables
ENV USER arkuser
ENV UID 1000
ENV GID 1000
ENV ASA_APPID 2430930
ENV SERVER_SHUTDOWN_TIMEOUT 30
ENV BASE_DIR /opt
ENV USER_SCRIPTS /home/${USER}/.local/bin

ENV STEAM_DIR ${BASE_DIR}/steam
ENV MANAGER_DIR ${BASE_DIR}/manager

ENV ARK_DIR ${STEAM_DIR}/steamapps/common/asa-server
ENV MANAGER_DIR ${BASE_DIR}/manager

# Wine variables
ENV STEAM_COMPAT_CLIENT_INSTALL_PATH ${ARK_DIR}
ENV STEAM_COMPAT_DATA_PATH ${STEAM_DIR}/steamapps/compatdata/${ASA_APPID}
ENV WINEDEBUG -all

# Log and pid file locations.
ENV LOG_FILE ${ARK_DIR}/ShooterGame/Saved/Logs/ShooterGame.log
ENV GAME_LOG_FILE ${ARK_DIR}/ShooterGame/Saved/Logs/ServerGame.*.log
ENV API_LOG_FILE ${ARK_DIR}/ShooterGame/Binaries/Win64/logs/ArkApi_*.log
ENV WINE_LOG_FILE ${ARK_DIR}/ShooterGame/Binaries/Win64/logs/wine.log

# Because steam is a 32 bit app, we need to add the i386 architecture
RUN set -ex; \
    dpkg --add-architecture i386

# Install the required packages
RUN set -ex; \
    apt update; \
    apt install -y --no-install-recommends \
    wget \
    curl \
    jq \
    iproute2 \
    locales \
    procps \
    software-properties-common \
    dbus \
    lib32gcc-s1 \
    libgcc-s1:amd64 \
    libgcc-s1:i386 \
    vim \
    unzip \
    winetricks;

# Add the winehq repository and install
RUN set -ex; \
    mkdir -pm755 /etc/apt/keyrings; \
    wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key; \
    wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources; \
    apt update; \
    apt install -y --install-recommends winehq-stable

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
RUN set -ex; mkdir -p ${USER_SCRIPTS} ${ARK_DIR} ${MANAGER_DIR} ${STEAM_DIR} ${STEAM_COMPAT_DATA_PATH}
RUN set -ex; chown -R ${USER}:${USER} /home/${USER} ${STEAM_DIR} ${MANAGER_DIR}

# Switch to the ark user so that the server files are owned by the ark user
USER ${USER}

# Add the ll alias. This is just a convenience thing just in case we have an image without it
RUN set -ex; echo "alias ll='ls -alF'" >> /home/${USER}/.bashrc
RUN set -ex; echo "export PATH='$PATH:/home/${USER}/.local/bin'" >> /home/${USER}/.bashrc
RUN set -ex; echo "alias ark='tail -f ${LOG_FILE} ${API_LOG_FILE}'" >> /home/${USER}/.bashrc

# Install bun
RUN set -ex; \
    curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}"

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
    rm -rf rcon.tar.gz rcon-0.10.3-amd64_linux

# Copy scripts to run the server
COPY --chown=${USER} --chmod=755 ./scripts/setup/entrypoint.sh /entrypoint.sh
COPY --chown=${USER} --chmod=755 ./scripts ${MANAGER_DIR}

# Create the symlink for the manager script. Linking to /usr/local/bin/manager allows us to run the script from anywhere
# RUN set -ex; ln -s ${MANAGER_DIR}/manager/manager.sh /usr/local/bin/manager
USER ${USER}

WORKDIR ${MANAGER_DIR}
ENTRYPOINT ["/entrypoint.sh"]
