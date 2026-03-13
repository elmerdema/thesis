# always, start from project root

export SDE_INSTALL=/usr/local/sde
uv run python3 p4src/deploy.py "$@"
