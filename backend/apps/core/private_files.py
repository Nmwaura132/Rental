import boto3
from botocore.config import Config
from django.conf import settings


def _s3_client(endpoint_url):
    return boto3.client(
        "s3",
        endpoint_url=endpoint_url,
        aws_access_key_id=settings.AWS_ACCESS_KEY_ID,
        aws_secret_access_key=settings.AWS_SECRET_ACCESS_KEY,
        config=Config(
            signature_version="s3v4",
            s3={"addressing_style": "path"},
        ),
        region_name="us-east-1",
    )


def _private_key(key):
    key = key.lstrip("/")
    if key.startswith("legacy:"):
        return key.removeprefix("legacy:")
    return key if key.startswith("private/") else f"private/{key}"


def upload_private_file(key, content, content_type, content_disposition=None):
    key = _private_key(key)
    extra = {
        "Bucket": settings.AWS_STORAGE_BUCKET_NAME,
        "Key": key,
        "Body": content,
        "ContentType": content_type,
    }
    if content_disposition:
        extra["ContentDisposition"] = content_disposition
    _s3_client(settings.AWS_S3_ENDPOINT_URL).put_object(**extra)
    return key


def private_file_url(key):
    return _s3_client(settings.AWS_S3_PUBLIC_ENDPOINT_URL).generate_presigned_url(
        "get_object",
        Params={
            "Bucket": settings.AWS_STORAGE_BUCKET_NAME,
            "Key": _private_key(key),
        },
        ExpiresIn=settings.AWS_QUERYSTRING_EXPIRE,
    )
