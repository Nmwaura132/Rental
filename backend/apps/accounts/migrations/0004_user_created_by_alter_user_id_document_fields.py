from django.conf import settings
from django.db import migrations, models
import django.db.models.deletion


def preserve_legacy_document_keys(apps, schema_editor):
    User = apps.get_model("accounts", "User")
    for user in User.objects.all().iterator():
        updates = []
        for field in ("id_front_photo", "id_back_photo"):
            value = getattr(user, field)
            if value and "/tenant-ids/" in value:
                key = f"legacy:tenant-ids/{value.split('/tenant-ids/', 1)[1]}"
                setattr(user, field, key)
                updates.append(field)
        if updates:
            user.save(update_fields=updates)


class Migration(migrations.Migration):
    dependencies = [
        ("accounts", "0003_user_id_back_photo_user_id_front_photo_and_more"),
    ]

    operations = [
        migrations.AddField(
            model_name="user",
            name="created_by",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="created_accounts",
                to=settings.AUTH_USER_MODEL,
            ),
        ),
        migrations.AlterField(
            model_name="user",
            name="id_back_photo",
            field=models.CharField(blank=True, max_length=500, null=True),
        ),
        migrations.AlterField(
            model_name="user",
            name="id_front_photo",
            field=models.CharField(blank=True, max_length=500, null=True),
        ),
        migrations.RunPython(
            preserve_legacy_document_keys,
            migrations.RunPython.noop,
        ),
    ]
