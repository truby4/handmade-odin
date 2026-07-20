#!/usr/bin/env bash
set -eu

mkdir -p build

bash scripts/build_game_code.sh

odin run src/platform \
	-out:build/handmade \
	-- \
	-internal:true \
	-slow-build:true
