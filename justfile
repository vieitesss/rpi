alias d := down
alias u := up
alias l := log
alias b := backup
alias bl := backup-list
alias br := restore

_default:
    just -l

down *flags:
    docker compose down {{flags}}

up *flags:
    docker compose up {{flags}}

log *flags:
    docker compose logs {{flags}}

# Backup commands
backup:
    bash scripts/backup.sh

backup-list:
    bash -c 'source .backup.env && export B2_ACCOUNT_ID B2_ACCOUNT_KEY RESTIC_REPOSITORY RESTIC_PASSWORD && restic snapshots'

# Restore commands
restore:
    @echo "Interactive restore menu"
    bash scripts/restore.sh

restore-list:
    bash scripts/restore.sh list

restore-volume volume snapshot="latest" service="":
    bash scripts/restore.sh volume {{volume}} {{snapshot}} {{service}}

restore-all-volumes snapshot="latest":
    bash scripts/restore.sh all-volumes {{snapshot}}

restore-media snapshot="latest" mode="merge":
    bash scripts/restore.sh media {{snapshot}} {{mode}}

restore-database snapshot="latest":
    bash scripts/restore.sh database {{snapshot}}

restore-list-volumes snapshot="latest":
    bash scripts/restore.sh list-volumes {{snapshot}}
