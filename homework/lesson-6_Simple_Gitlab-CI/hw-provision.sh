#!/usr/bin/env bash
# Provisioning homework actions
set -euo pipefail

# HW pipeline generate
cp ./project_file_gitlab-ci.yml ../../projects/cocktail-search/.gitlab-ci.yml

# Start UI for one-click provisioning of a GitLab lab
/bin/bash ../../scripts/start-lab-dashboard.sh