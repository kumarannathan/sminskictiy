#!/usr/bin/env bash
# Syntax-check Luau without Studio.
#
# WHY THIS EXISTS. Until now the only compiler in this project was Studio, so
# a typo in game/*.lua was not found until somebody synced and pressed Play.
# luau-analyze parses the same grammar Roblox does and finds it in a second.
#
# WHAT IS FILTERED, AND WHY THAT IS SAFE. luau-analyze knows nothing about the
# Roblox environment, so it reports every `game`, `workspace`, `task`, `Enum`,
# `Instance`, `script`, `Color3`, `UDim2` ... as an unknown global -- about
# 10,700 lines of it here, none of it a defect. Those are dropped. SYNTAX
# errors are not environment-dependent and are never filtered: if this script
# is quiet, the files parse.
#
# It is NOT a type checker. Without Roblox type definitions the type errors
# are meaningless, so this deliberately only answers "does it parse".
#
#   tools/check.sh                # everything in game/
#   tools/check.sh game/UI.lua    # one file
set -uo pipefail
cd "$(dirname "$0")/.."

files=("$@")
if [ ${#files[@]} -eq 0 ]; then
	files=(game/*.lua)
fi

if ! command -v luau-analyze >/dev/null 2>&1; then
	echo "luau-analyze not found -- brew install luau" >&2
	exit 127
fi

# WHITELIST, NOT BLACKLIST. An earlier version dropped the known-noisy
# messages and let everything else through, which meant every new category
# luau-analyze invented (SameLineStatement, inference bail-outs) turned into a
# spurious failure. Only genuine parse failures are matched now, so this
# script fails for one reason and it is always a real one.
out=$(luau-analyze --formatter=plain "${files[@]}" 2>&1 \
	| grep -Ei "SyntaxError|Expected .* but got|Unexpected|Malformed|Incomplete statement")

if [ -n "$out" ]; then
	echo "$out"
	echo
	echo "FAIL: ${#files[@]} file(s) checked, see above"
	exit 1
fi

echo "ok: ${#files[@]} file(s) parse"
# the balance checker catches a class of mistake luau-analyze does not care
# about (a stray end that still parses as something legal)
python3 art/tools/luacheck_balance.py "${files[@]}"
