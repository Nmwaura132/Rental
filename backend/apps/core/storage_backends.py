from django.conf import settings
from django.core.files.storage import default_storage
from storages.backends.s3boto3 import S3Boto3Storage

class PublicMediaStorage(S3Boto3Storage):
    location = 'public'
    default_acl = 'private'
    file_overwrite = False
    querystring_auth = True
    custom_domain = False

class PrivateMediaStorage(S3Boto3Storage):
    location = 'private'
    default_acl = 'private'
    file_overwrite = False
    querystring_auth = True  # Enable signed URLs
    custom_domain = False    # Avoid using public URL for private files


def private_media_storage():
    """
    Resolve the storage backend for private uploads at field-definition time.

    WHY a module-level callable: Django keeps a reference to the callable and
    deconstructs *that* into migrations, so the recorded field state is the same
    whether or not S3 is configured. Branching on `settings.USE_S3` inline made
    the deconstructed value environment-dependent, which flipped
    `makemigrations --check` between pass and fail depending on the env.
    """
    return PrivateMediaStorage() if settings.USE_S3 else default_storage
