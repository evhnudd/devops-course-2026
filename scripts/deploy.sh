#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                     # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"   # требование 2: из любого каталога
LOCAL_DIR="${REPO_ROOT}/site/"

err() { echo "deploy: $*" >&2; }

# 1. Разбор аргумента --dry-run
DRY_RUN=""
case "${1:-}" in
    "")        ;;
    --dry-run) DRY_RUN="--dry-run" ;;
    *)         err "неизвестный аргумент: $1"; echo "Использование: $0 [--dry-run]" >&2; exit 1 ;;
esac

# 2. Проверки по требованиям 4 и 5
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    err "файл site/index.html отсутствует, доставка отменена"
    exit 1
fi
if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
    err "в репозитории есть незафиксированные изменения, доставка отменена:"
    git -C "$REPO_ROOT" status --short >&2
    exit 1
fi
COMMIT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"

# 3. Синхронизация (одно SSH-соединение, без интерактивного запроса пароля)
rsync -avz --delete --chmod=D755,F644 ${DRY_RUN} \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
    "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

# 4. При --dry-run — завершение без проверки доступности
if [[ -n "$DRY_RUN" ]]; then
    echo "dry-run: план выведен, состояние сервера не изменено (коммит ${COMMIT})"
    exit 0
fi

# 5. Проверка доступности с проверкой сертификата
if ! curl -fsS --cacert "$CA_CERT" -o /dev/null --max-time 5 "$SITE_URL"; then
    err "ресурс ${SITE_URL} недоступен после доставки"
    exit 1
fi
echo "Доставлен коммит ${COMMIT}"
