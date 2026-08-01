from django.conf import settings


def test_money_and_notification_tasks_use_separate_queues():
    assert settings.CELERY_TASK_ROUTES["apps.payments.tasks.*"]["queue"] == "payments"
    assert (
        settings.CELERY_TASK_ROUTES["apps.notifications.tasks.*"]["queue"]
        == "notifications"
    )
