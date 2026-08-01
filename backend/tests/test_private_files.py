from apps.core import private_files


class FakeS3Client:
    def __init__(self):
        self.put_kwargs = None
        self.signed_kwargs = None

    def put_object(self, **kwargs):
        self.put_kwargs = kwargs

    def generate_presigned_url(self, operation, Params, ExpiresIn):
        self.signed_kwargs = {
            "operation": operation,
            "params": Params,
            "expires": ExpiresIn,
        }
        return "https://files.example.test/signed-private-file"


def test_private_upload_uses_private_prefix(monkeypatch, settings):
    client = FakeS3Client()
    monkeypatch.setattr(private_files, "_s3_client", lambda endpoint: client)
    settings.AWS_S3_ENDPOINT_URL = "http://minio:9000"
    settings.AWS_STORAGE_BUCKET_NAME = "assets"

    key = private_files.upload_private_file(
        "tenant-ids/1/front.jpg",
        b"photo",
        "image/jpeg",
    )

    assert key == "private/tenant-ids/1/front.jpg"
    assert client.put_kwargs["Key"] == key
    assert client.put_kwargs["ContentType"] == "image/jpeg"


def test_private_url_is_signed_against_public_endpoint(monkeypatch, settings):
    client = FakeS3Client()
    captured_endpoint = []

    def fake_client(endpoint):
        captured_endpoint.append(endpoint)
        return client

    monkeypatch.setattr(private_files, "_s3_client", fake_client)
    settings.AWS_S3_PUBLIC_ENDPOINT_URL = "https://files.example.test"
    settings.AWS_STORAGE_BUCKET_NAME = "assets"
    settings.AWS_QUERYSTRING_EXPIRE = 900

    url = private_files.private_file_url("private/reports/report.pdf")

    assert url == "https://files.example.test/signed-private-file"
    assert captured_endpoint == ["https://files.example.test"]
    assert client.signed_kwargs["params"]["Key"] == "private/reports/report.pdf"
    assert client.signed_kwargs["expires"] == 900
