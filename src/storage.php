<?php
// File storage for capsule attachments.
//
// This is the only file that reads or writes uploaded files. They are kept in Amazon S3,
// in the bucket S3_BUCKET under the prefix "uploads/". The rest of the app only uses the
// three functions storage_save(), storage_delete() and storage_stream().
//
// There are no access keys here or in .env: on EC2 the SDK takes the temporary credentials
// of the server's IAM role (timecapsule-dev-app-role) from the instance metadata service.

use Aws\S3\S3Client;

const STORAGE_PREFIX = 'uploads/';
// How long a download link given to the browser stays valid.
const STORAGE_LINK_TTL = '+5 minutes';

// One S3 client per request, created on first use.
function s3_client(): S3Client
{
    static $client = null;
    if ($client === null) {
        $client = new S3Client(['region' => config('AWS_REGION', 'eu-central-1')]);
    }
    return $client;
}

function s3_bucket(): string
{
    $bucket = config('S3_BUCKET');
    if ($bucket === null) {
        throw new RuntimeException('S3_BUCKET is not set.');
    }
    return $bucket;
}

// Object key of a stored file. basename() makes sure the key never leaves "uploads/".
function storage_key(string $storedName): string
{
    return STORAGE_PREFIX . basename($storedName);
}

// Upload a file ($_FILES['...'] entry) to S3 and return its stored name, e.g. "3f9a...e1.png".
// The name is random, so users cannot guess other people's file names.
function storage_save(array $uploadedFile, string $extension): string
{
    $storedName = bin2hex(random_bytes(16)) . '.' . $extension;

    s3_client()->putObject([
        'Bucket'      => s3_bucket(),
        'Key'         => storage_key($storedName),
        'SourceFile'  => $uploadedFile['tmp_name'],
        'ContentType' => mime_content_type($uploadedFile['tmp_name']) ?: 'application/octet-stream',
    ]);
    return $storedName;
}

// With versioning on, this only adds a delete marker; old versions are removed by the
// lifecycle rule. The app role is not allowed to delete versions.
function storage_delete(?string $storedName): void
{
    if ($storedName === null || $storedName === '') {
        return;
    }

    s3_client()->deleteObject([
        'Bucket' => s3_bucket(),
        'Key'    => storage_key($storedName),
    ]);
}

// Send the browser to a presigned S3 link instead of streaming the file through PHP.
// $disposition: "inline" (show in the browser) or "attachment" (download).
// Access rights are checked by the caller before this function is called.
function storage_stream(string $storedName, string $mime, string $downloadName, string $disposition): never
{
    // Keep only safe characters for the plain filename; the UTF-8 name goes in filename*.
    $asciiName = preg_replace('/[^A-Za-z0-9._ -]/', '_', $downloadName);

    $client = s3_client();
    $command = $client->getCommand('GetObject', [
        'Bucket'                     => s3_bucket(),
        'Key'                        => storage_key($storedName),
        // S3 returns the file with these headers, the same ones the old code sent itself.
        'ResponseContentType'        => $mime,
        'ResponseContentDisposition' => sprintf(
            '%s; filename="%s"; filename*=UTF-8\'\'%s',
            $disposition,
            $asciiName,
            rawurlencode($downloadName)
        ),
    ]);
    $url = (string) $client->createPresignedRequest($command, STORAGE_LINK_TTL)->getUri();

    // The link expires, so the redirect itself must not be cached.
    header('Cache-Control: no-store');
    redirect($url);
}
