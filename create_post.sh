#!/bin/sh

POST_DIR="_posts"
DATE=$(date +"%Y-%m-%d")

if [ $# -eq 0 ]; then
    echo "Usage: $(basename $0) title"
    exit 1
fi

TITLE="$(echo "$@" | tr " " "-")"
TITLE="$DATE-$TITLE.md"

if [ -f "$POST_DIR/$TITLE" ]; then
    echo "$POST_DIR/$TITLE already exists"
    exit
fi

cat > "$POST_DIR/$TITLE" <<EOF
---
layout: post
title: "$@"
date: $(date +"%Y-%m-%d %H:%MM:%S")
---
EOF
