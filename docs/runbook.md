# Operator runbook

## Initial host setup
```bash
git clone https://github.com/ResurgenceStation/infrastructure /srv/resurgence/infrastructure
cd /srv/resurgence/infrastructure
git submodule update --init slimbus
ln -sf globals.env .env
bash deploy/install-host.sh
bash deploy/populate-secrets.sh
bash deploy/install-eventscripts.sh
```

## Deploy infrastructure change
```bash
cd /srv/resurgence/infrastructure && git pull
bash deploy/install-eventscripts.sh    # if EventScripts or globals changed
docker-compose up -d --build <service>  # for service changes
```

## Deploy config change (game-side runtime values)
Operator PRs to `ResurgenceStation/config`. Next round's `update-config.sh` (fired by
TGS PreCompile event) picks it up automatically.

## Deploy game-code change
PR to `ResurgenceStation/ResurgenceStation`. TGS auto-deploys on master push.
