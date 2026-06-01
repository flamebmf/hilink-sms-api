#!/bin/sh
# Pre-push check: ensure no working configs are staged for commit
# Install as: cp check-push.sh .git/hooks/pre-push && chmod +x .git/hooks/pre-push

STAGED=$(git diff --cached --name-only)
ERRORS=""

for f in $STAGED; do
    case "$f" in
        hilink-auth.conf|zabbix_hilink_sms_webhook.yaml)
            [ -f ".gitignore" ] && grep -q "^$f$" .gitignore && continue
            ERRORS="$ERRORS  - $f (use .default version for public)\n"
            ;;
    esac
done

if [ -n "$ERRORS" ]; then
    echo "ERROR: Working config files detected in commit:"
    printf "$ERRORS"
    echo "Commit/Push rejected. Use the .default versions instead."
    exit 1
fi

exit 0
