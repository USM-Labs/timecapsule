# События TimeCapsule

С ЛР7 веб-сервер не выполняет фоновую работу сам. Он публикует события в тему Amazon SNS `timecapsule-dev-events` (регион `eu-central-1`), а дальше их обрабатывают функции AWS Lambda.

| Событие | Кто публикует | Кто получает |
| --- | --- | --- |
| `capsule.sealed` | сервер приложения (`src/events.php`) при `Seal capsule` | очередь `timecapsule-dev-mail` → `timecapsule-dev-mailer` |
| `capsules.opened` (запись о вызове) | служба Lambda: назначение `OnSuccess` у `timecapsule-dev-opener` | очередь `timecapsule-dev-mail` → `timecapsule-dev-mailer`; почта (только если `count > 0`) |

Подписка очереди использует `Raw message delivery`, поэтому тело сообщения SQS совпадает с телом события. Оба формата - JSON в кодировке UTF-8, время всегда в UTC в формате ISO 8601 с `Z`.

## `capsule.sealed`

Публикуется один раз, сразу после того как строка капсулы записана в базу.

```json
{
  "type": "capsule.sealed",
  "version": 1,
  "event_id": "4b1c0a9e7d2f4e7c9a1f0b3d5e6c7a8b",
  "occurred_at": "2026-11-23T08:15:02Z",
  "capsule_id": 12,
  "user_id": 2,
  "open_at": "2026-11-23T08:19:00Z"
}
```

| Поле | Тип | Смысл |
| --- | --- | --- |
| `type` | string | всегда `capsule.sealed`; по нему фильтр подписки и `timecapsule-dev-mailer` отличают события |
| `version` | integer | версия формата; при несовместимом изменении увеличивается, и получатель может обрабатывать обе |
| `event_id` | string, 32 hex | случайный идентификатор события, попадает в журналы Lambda и помогает найти повтор |
| `occurred_at` | string | когда событие опубликовано |
| `capsule_id` | integer | `capsules.id` |
| `user_id` | integer | владелец капсулы, `users.id` |
| `open_at` | string | когда капсула откроется |

Атрибут сообщения SNS: `type` (String) = `capsule.sealed`.

**Что не передаётся.** В событии нет заголовка, текста капсулы, вложения, адресов почты и других личных данных. `timecapsule-dev-mailer` читает заголовок и адресата из базы по `capsule_id`. Поэтому:

- сообщение, которое лежит в очереди или DLQ до 14 дней, видно в консоли и журналах, но не раскрывает содержимое капсулы;
- если капсулу изменили или удалили, пока событие ждало в очереди, письмо строится по актуальным данным (удалённая капсула просто пропускается);
- размер события постоянный и маленький.

## `capsules.opened` (запись о вызове `timecapsule-dev-opener`)

Раз в минуту EventBridge Scheduler (`timecapsule-dev-open-capsules`) асинхронно вызывает `timecapsule-dev-opener`. После каждого успешного вызова служба Lambda публикует в тему запись о вызове (invocation record). Поле `responsePayload` - то, что вернула функция:

```json
{
  "version": "1.0",
  "timestamp": "2026-11-23T08:19:01.204Z",
  "requestContext": {
    "requestId": "c6af9ac6-7b61-11e6-9a41-93e812345678",
    "functionArn": "arn:aws:lambda:eu-central-1:<account>:function:timecapsule-dev-opener:$LATEST",
    "condition": "Success",
    "approximateInvokeCount": 1
  },
  "requestPayload": { "...": "событие EventBridge Scheduler" },
  "responseContext": { "statusCode": 200, "executedVersion": "$LATEST" },
  "responsePayload": {
    "type": "capsules.opened",
    "version": 1,
    "opened_at": "2026-11-23T08:19:01Z",
    "count": 1,
    "capsules": [
      { "capsule_id": 12, "title": "Lab 07 - opens in 4 minutes", "open_at": "2026-11-23T08:19:00Z" }
    ]
  }
}
```

| Поле `responsePayload` | Тип | Смысл |
| --- | --- | --- |
| `type` | string | всегда `capsules.opened` |
| `version` | integer | версия формата |
| `opened_at` | string | момент, который функция записала в `capsules.opened_at` |
| `count` | integer | сколько капсул открыто в этом вызове, может быть `0` |
| `capsules[]` | array | открытые капсулы: `capsule_id`, `title`, `open_at` |

У записи о вызове нет атрибутов сообщения SNS, поэтому подписки фильтруют по телу (`FilterPolicyScope` = `MessageBody`). Заголовок капсулы здесь есть, потому что эта запись приходит на почту владельцу; текста капсулы и адресов в ней нет.

## Подписки на тему

| Подписка | Фильтр (`MessageBody`) | Зачем |
| --- | --- | --- |
| SQS `timecapsule-dev-mail`, raw | `{"$or":[{"type":["capsule.sealed"]},{"responsePayload":{"type":["capsules.opened"],"count":[{"numeric":[">",0]}]}}]}` | `timecapsule-dev-mailer` получает запечатывания и только непустые записи об открытии, а не пустую запись каждую минуту |
| Email `mox7.sp1avsk1@gmail.com` | `{"responsePayload":{"type":["capsules.opened"],"count":[{"numeric":[">",0]}]}}` | на почту приходят только открытые капсулы |

## Повторы

SQS доставляет сообщение хотя бы один раз, поэтому одно событие может прийти дважды. У таблицы `notifications` есть уникальный индекс `(capsule_id, kind)`, где `kind` равен `sealed` или `opened`, а `timecapsule-dev-mailer` пишет через `INSERT ... ON CONFLICT DO NOTHING`. Повтор не создаёт второе уведомление, а перед паузой `MAIL_DELAY_SECONDS` функция проверяет, нет ли уведомления, и на повторе не ждёт. `timecapsule-dev-opener` открывает капсулы одним `UPDATE ... WHERE opened_at IS NULL ... RETURNING`, поэтому каждая капсула попадает в `capsules.opened` один раз, даже если два вызова идут одновременно.
