#!/bin/bash
# Убирает временный NAT Gateway, созданный nat-up.sh:
# удаляет маршрут из private-rt, удаляет NAT Gateway, ждёт удаления и освобождает Elastic IP.
set -euo pipefail

AWS_REGION=eu-central-1
ROUTE_TABLE_ID=rtb-06aebc01e03f7ed9f    # timecapsule-dev-private-rt
STATE_FILE="$(dirname "$0")/nat-state.env"
export AWS_REGION AWS_PAGER=""

if [ ! -f "$STATE_FILE" ]; then
    echo "Нет файла $STATE_FILE: нечего удалять (nat-up.sh не запускался?)." >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$STATE_FILE"
: "${NAT_ID:?в $STATE_FILE нет NAT_ID}" "${ALLOCATION_ID:?в $STATE_FILE нет ALLOCATION_ID}"

echo "==> Удаляем маршрут 0.0.0.0/0 из private-rt"
aws ec2 delete-route --route-table-id "$ROUTE_TABLE_ID" --destination-cidr-block 0.0.0.0/0 \
    || echo "    маршрута уже нет, продолжаем"

echo "==> Удаляем NAT Gateway $NAT_ID"
aws ec2 delete-nat-gateway --nat-gateway-id "$NAT_ID" --output text >/dev/null

echo "==> Ждём удаления NAT Gateway"
aws ec2 wait nat-gateway-deleted --nat-gateway-ids "$NAT_ID"

echo "==> Освобождаем Elastic IP $ALLOCATION_ID"
# Шлюз отпускает адрес не сразу после перехода в deleted, поэтому несколько попыток с паузой.
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if aws ec2 release-address --allocation-id "$ALLOCATION_ID" 2>/dev/null; then
        echo "    освобождён (попытка $attempt)"
        rm -f "$STATE_FILE"
        echo "Готово. NAT Gateway удалён, Elastic IP освобождён."
        exit 0
    fi
    echo "    адрес ещё привязан, ждём 15 секунд (попытка $attempt)"
    sleep 15
done

echo "Не удалось освободить $ALLOCATION_ID. Освободите вручную: aws ec2 release-address --allocation-id $ALLOCATION_ID" >&2
exit 1
