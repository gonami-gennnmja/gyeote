FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    curl git tmux sudo jq unzip xz-utils ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash devuser \
    && echo "devuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER devuser
WORKDIR /home/devuser

RUN curl -fsSL https://claude.ai/install.sh | bash

ENV PATH="/home/devuser/.local/bin:${PATH}"
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

RUN git config --global user.name "가인" \
    && git config --global user.email "gain11131113@gmail.com" \
    && git config --global credential.helper store \
    && git config --global --add safe.directory /workspace

COPY --chown=devuser:devuser entrypoint.sh /home/devuser/entrypoint.sh
RUN chmod +x /home/devuser/entrypoint.sh \
    && mkdir -p /home/devuser/scripts

ENTRYPOINT ["/home/devuser/entrypoint.sh"]
