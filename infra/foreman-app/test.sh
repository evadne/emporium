#!/usr/bin/env sh

nonce=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
export ROLE="TEST"
export NODE_NAME="$ROLE-$nonce@localhost"
export NODE_COOKIE="emporium-local"

cd "`dirname $0`/../.." && elixir --sname $NODE_NAME --cookie $NODE_COOKIE -S mix test $@
