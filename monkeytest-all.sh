#!/bin/bash
# License::   GPLv3+
# Copyright:: 2019 Daniel Barrows
# Status::    beta
# Source::    https://github.com/daniel-barrows/MonkeyTest
# Description:: Run MonkeyTest on multiple drives and output results as a CSV
#               with some additional information on the drives.
# Dependencies:: jq, MonkeyTest

EXIT_USAGE_ERROR=7

find_symlink_in_dir(){
  symlink="$1"
  if [ -z "$symlink" ] || [ "$#" -gt 2 ]; then
    echo "ERROR: find_symlink_in_dir requires one or two arguments. (Given $#)" >&2
    echo 'USAGE: find_symlink_in_dir $symlink_target [ $dir ]' >&2
    return $EXIT_USAGE_ERROR
  fi
  dir="$2"
  [ -z "$dir" ] && dir='.'
  for i in "$dir"/*; do
    if [ "$( readlink -f "$i" )" = "$target_path" ]; then
      basename -- "$i"
      return 0
    fi
  done
  return 1
}

# I haven't actually tested which special characters get replaced and which
# don't. Please file bug reports with references or test results.
# Adapted from https://gist.github.com/cdown/1163649
encode_diskname(){
  local l=${#1}
  for (( i = 0 ; i < l ; i++ )); do
    local c=${1:i:1}
    case "$c" in
      [a-zA-Z0-9._-]) printf "$c" ;;
      *            ) printf '\\x%.2X' "'$c" ;;
    esac
  done
}

decode_diskname(){
  while read; do echo -e ${REPLY//\x/\\x}; done <<<"$1"
}

get_port_for_label(){
  target_path="$( readlink -f "/dev/disk/by-label/$( encode_diskname "$1" )" )"
  find_symlink_in_dir "$target_path" /dev/disk/by-path
}

print_speed_header(){
  echo "Computer,Date,Label,Path,Port,Read rate (MB/s),Write rate (MB/s)"
}

# Output the results of a speed test to the directory at $path
#
# Other lsusb attributes that may be worth recording:
# - MaxPower
# - bcdUSB
# - Device
test_speed_for_dir(){
  path="$1"
  print_header="$2"
  [ -z "$print_header" ] && print_speed_header
  label="$( basename -- "$path" )"
  #path="$( find /media -maxdepth 2 -name "$label" 2>/dev/null )"
  monkeytest.py -f "$path/testfile" -j "/tmp/$label.json" > /dev/null
  return_value=$?
  if [ $return_value -eq 0 ]; then
    echo -n "$HOSTNAME,$( date -Idate ),$label,$path,"
    echo -n "$( get_port_for_label "$label" ),"
    echo -n "$( jq '.["Write speed in MB/s"]' < "/tmp/$label.json" ),"
    echo    "$( jq '.["Read speed in MB/s"]' < "/tmp/$label.json" )"
    rm -f "/tmp/$label.json"
  fi
  return $return_value
}

test_speed_for_dirs(){
  local print_header=true
  local ignore_unwritable=
  while true; do
    case "$1" in
      --no-header         ) print_header=; shift;;
      --ignore-unwritable ) ignore_unwritable=true; shift;;
      * ) break;;
    esac
  done
  [ -z "$print_header" ] && print_speed_header
  for i in "$@"; do
    if [ -w "$i" ]; then
      test_speed_for_dir "$i" --no-header
    elif ! [ -z "$ignore-unwritable" ]; then
      echo "WARNING: No write access for $i. Skipping..." >&2
    fi
  done
}

test_speed_all_drives(){
  test_speed_for_dirs --ignore-unwritable /media/*/* /tmp ~
}

test_speed_external_drives(){
  test_speed_for_dirs --ignore-unwritable /media/*/*
}

# Source: https://stackoverflow.com/a/28776166
if ! (return 0 2>/dev/null); then
  if [ "$1" = --all ]; then
    shift
    test_speed_all_drives "$@"
  else
    test_speed_external_drives "$@"
  fi
fi
