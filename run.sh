#!/usr/bin/env bash

# If i want to create builds in future..
# mkdir -p bin
# odin build src -out:build/handmade
mkdir -p build
odin run src -out:build/handmade
