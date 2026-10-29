#!/bin/bash

set -euo pipefail

sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2 git
sudo service docker start
sudo usermod -aG docker "$USER"

runtime="$HOME/etg-frappe-runtime"
mkdir -p "$runtime"
cp -R /mnt/c/Dev/SalesIntelligence/etg-frappe-crm/docker/. "$runtime/"

cd "$runtime"
sudo docker compose up -d
sudo docker compose ps

printf '\nETG Frappe CRM is starting. Open http://crm.localhost:8000/crm after five minutes.\n'
printf 'Local username: Administrator\n'
printf 'Local password: admin\n'
