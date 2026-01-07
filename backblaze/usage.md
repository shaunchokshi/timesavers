Example invocations

Local per-host backup (using your loader as JSON logger):

./b2_env_loader_and_dispatch.sh --run-local \
 'HOSTNAME_SHORT=$(hostname -s); REMOTE="b2crypt:${HOSTNAME_SHORT}-backups"; \
  ~/scripts/b2_synclist_runner.sh --remote "$REMOTE" --retention-hours 96 --symlinks follow-and-record --subdir fullpath'


Multi-host fan-out (each host uses its own synclist):

./b2_env_loader_and_dispatch.sh --run-multi 'x6,P370-C' \
 'HOSTNAME_SHORT=$(hostname -s); REMOTE="b2crypt:${HOSTNAME_SHORT}-backups"; \
  ~/scripts/b2_synclist_runner.sh --remote "$REMOTE" --retention-hours 96 --symlinks follow-and-record --subdir fullpath'


