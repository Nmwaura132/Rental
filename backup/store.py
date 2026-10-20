"""The backup bucket in MinIO: make sure it exists, upload a dump, drop old dumps.

WHY Python and not MinIO's `mc`: MinIO stopped publishing `mc` downloads
(dl.min.io answers 410 Gone) and its Docker image, so the image could no
longer be built. boto3 speaks the same S3 API and installs from PyPI.

Usage:
    store.py ensure-bucket
    store.py upload FILE
    store.py prune DAYS
"""
import os
import sys
from datetime import datetime, timedelta, timezone

import boto3
from botocore.exceptions import ClientError


def _client():
    return boto3.client(
        "s3",
        endpoint_url=os.environ.get("MINIO_ENDPOINT", "http://minio:9000"),
        aws_access_key_id=os.environ["MINIO_ROOT_USER"],
        aws_secret_access_key=os.environ["MINIO_ROOT_PASSWORD"],
        region_name="us-east-1",
    )


def ensure_bucket(s3, bucket):
    try:
        s3.head_bucket(Bucket=bucket)
    except ClientError:
        s3.create_bucket(Bucket=bucket)


def upload(s3, bucket, path):
    s3.upload_file(path, bucket, os.path.basename(path))


def prune(s3, bucket, days):
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket):
        for obj in page.get("Contents", []):
            if obj["LastModified"] < cutoff:
                s3.delete_object(Bucket=bucket, Key=obj["Key"])


def main(argv):
    bucket = os.environ.get("BACKUP_BUCKET", "kasa-backups")
    s3 = _client()
    command = argv[1] if len(argv) > 1 else ""
    if command == "ensure-bucket":
        ensure_bucket(s3, bucket)
    elif command == "upload" and len(argv) == 3:
        upload(s3, bucket, argv[2])
    elif command == "prune" and len(argv) == 3:
        prune(s3, bucket, int(argv[2]))
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
