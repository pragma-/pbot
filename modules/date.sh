#!/bin/bash

export TZ=UTC
if (( $# )) && ! read -r TZ < <(IFS=_; find -L /usr/share/zoneinfo/posix -type f -not -iname 'West' -iname "*$**" -printf '%P\n' -quit); then
  echo "No match for '$*'."
  exit 1
fi
if [[ $TZ != UTC ]]; then
  _city=${TZ##*/}
  echo "It's $(date) in ${_city//_/ }."
else
  echo "It's $(date)."
fi
