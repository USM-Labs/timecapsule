<?php
// LR7: background work is done by AWS Lambda.
//
// When EVENTS_TOPIC_ARN is set, the web server does not "send" the e-mail itself and does not
// open capsules on every request. It only publishes an event to the SNS topic and answers the
// user right away; timecapsule-dev-mailer and timecapsule-dev-opener do the rest
// (see docs/events.md). With an empty EVENTS_TOPIC_ARN (local Docker) the old in-request
// behaviour from mailer.php and open_due_capsules() is used.

function events_enabled(): bool
{
    return config('EVENTS_TOPIC_ARN', '') !== '';
}

// Publish one event. The body carries only ids and times: the mailer reads the title and the
// recipient from the database, so no personal data or capsule text travels through SNS/SQS.
function event_publish(string $type, array $data): void
{
    static $client = null;
    $client ??= new Aws\Sns\SnsClient([
        'region' => config('AWS_REGION', 'eu-central-1'),
        'version' => 'latest',
    ]);

    $event = [
        'type' => $type,
        'version' => 1,
        'event_id' => bin2hex(random_bytes(16)),
        'occurred_at' => gmdate('Y-m-d\TH:i:s\Z'),
    ] + $data;

    $client->publish([
        'TopicArn' => config('EVENTS_TOPIC_ARN'),
        'Message' => json_encode($event, JSON_UNESCAPED_SLASHES),
        'MessageAttributes' => [
            'type' => ['DataType' => 'String', 'StringValue' => $type],
        ],
    ]);
}
