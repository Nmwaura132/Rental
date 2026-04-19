import django.db.models.deletion
import django.utils.timezone
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('payments', '0003_stk_push_model'),
    ]

    operations = [
        migrations.CreateModel(
            name='BankPaymentNotification',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('bank', models.CharField(
                    choices=[('kcb', 'KCB'), ('equity', 'Equity')],
                    db_index=True,
                    max_length=10,
                )),
                ('transaction_ref', models.CharField(db_index=True, max_length=100, unique=True)),
                ('amount', models.DecimalField(decimal_places=2, max_digits=10)),
                ('payer_name', models.CharField(blank=True, max_length=120)),
                ('payer_account', models.CharField(blank=True, max_length=60)),
                ('payment_ref', models.CharField(blank=True, max_length=100)),
                ('credited_at', models.DateTimeField()),
                ('raw_payload', models.JSONField()),
                ('status', models.CharField(
                    choices=[('unmatched', 'Unmatched'), ('matched', 'Matched'), ('duplicate', 'Duplicate')],
                    db_index=True,
                    default='unmatched',
                    max_length=12,
                )),
                ('received_at', models.DateTimeField(auto_now_add=True)),
                ('payment', models.OneToOneField(
                    blank=True,
                    null=True,
                    on_delete=django.db.models.deletion.SET_NULL,
                    related_name='bank_notification',
                    to='payments.payment',
                )),
            ],
            options={
                'db_table': 'bank_payment_notifications',
                'ordering': ['-credited_at'],
                'indexes': [
                    models.Index(fields=['bank', 'status'], name='bank_notif_bank_status_idx'),
                    models.Index(fields=['credited_at'], name='bank_notif_credited_at_idx'),
                ],
            },
        ),
    ]
