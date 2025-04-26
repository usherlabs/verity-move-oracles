#!/bin/bash

usage() {
  echo "Usage: $0 [-a address]"
  exit 1
}

ADDRESS=""

# Parse command-line arguments (optional -a flag)
while getopts ":a:" opt; do
  case "$opt" in
    a)
      ADDRESS="$OPTARG"
      ;;
    \?)
      echo "Invalid option: -$OPTARG"
      usage
      ;;
    :)
      echo "Option -$OPTARG requires an argument."
      usage
      ;;
  esac
done

# Check if rooch exists
if ! command -v rooch &> /dev/null; then
  echo "Error: rooch command not found. Please install rooch."
  exit 1
fi

# Check for active network environment using 'rooch env list'
ACTIVE_ALIAS=$(rooch env list | awk -F '│' '$0 ~ /True/ {gsub(/^ +| +$/, "", $2); print $2; exit}')

if [ -z "$ACTIVE_ALIAS" ]; then
  echo "Error: No active environment is set. Please set an active environment using 'rooch env set <env alias>'"
  exit 1
else
  echo "Active environment: $ACTIVE_ALIAS"
fi

# Execute the rooch account balance command, with the address if provided
if [ -z "$ADDRESS" ]; then
  rooch account balance
else
  rooch account balance -a "$ADDRESS"
fi
