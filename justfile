alias d := down
alias u := up
alias l := log
alias b := backup
alias bl := backup-list
alias br := backup-restore

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

backup-restore:
    bash scripts/restore.sh
