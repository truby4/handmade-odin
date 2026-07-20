#!/usr/bin/env bash
set -eu

mkdir -p build

odin build src/game \
	-build-mode:dll \
	-out:build/libhandmade.so
