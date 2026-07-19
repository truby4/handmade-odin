#!/usr/bin/env bash

#!/usr/bin/env bash
set -eu

mkdir -p build

odin build src/game \
	-build-mode:dll \
	-out:build/libhandmade.so

odin run src/platform \
	-out:build/handmade \
	-- \
	-internal:true \
	-slow-build:true
