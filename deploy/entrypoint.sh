#!/bin/bash
if [ ! -d /workspace/.git ]; then
    git clone https://github.com/gonami-gennnmja/gyeote.git /workspace
fi
git config --global --add safe.directory /workspace
cp -n /workspace/.claude/scripts/start-team.sh /home/devuser/scripts/start-team.sh 2>/dev/null
chmod +x /home/devuser/scripts/start-team.sh 2>/dev/null
sleep infinity
