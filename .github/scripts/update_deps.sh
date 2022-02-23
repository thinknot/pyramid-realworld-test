#!/usr/bin/env bash

set -xeu

# Fetch unshallow
git fetch --unshallow

# Update the ./nix/sources.json with the latest version of the branch
niv update

# Update Python packages
poetry lock

# Only continue if there are any changes
if ! git diff-index --quiet HEAD; then
  today=$(date -I)
  # Commit the new changes and push them to the repository so a PR can be opened
  git checkout -b "package-update-$today"
  git config user.name "Package updater"
  git config user.email "gh-bot@niteo.co"
  git commit -a -m "Package update $today"
  git push -u origin "package-update-$today"
  gh auth login --with-token <<< $GITHUB_TOKEN
  gh pr create -B master -H "package-update-$today" -t "Update packages" -b ""
fi
