from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('payments', '0004_bank_payment_notification'),
    ]

    operations = [
        migrations.AddField(
            model_name='payment',
            name='bank_name',
            field=models.CharField(blank=True, max_length=50, null=True),
        ),
        migrations.AddField(
            model_name='payment',
            name='bank_account',
            field=models.CharField(blank=True, max_length=40, null=True),
        ),
        migrations.AddField(
            model_name='payment',
            name='bank_reference',
            field=models.CharField(blank=True, max_length=100, null=True),
        ),
        migrations.AddField(
            model_name='payment',
            name='bank_branch',
            field=models.CharField(blank=True, max_length=80, null=True),
        ),
    ]
