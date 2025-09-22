_default:
    just -l

down *flags:
    docker compose down {{flags}}

up *flags:
    docker compose up {{flags}}

log *flags:
    docker compose logs {{flags}}
