from django.urls import path
from .views import MarkReadView, NotificationListView, UnreadCountView

urlpatterns = [
    path("", NotificationListView.as_view(), name="notifications"),
    path("unread-count/", UnreadCountView.as_view(), name="notifications-unread-count"),
    path("mark-read/", MarkReadView.as_view(), name="notifications-mark-read"),
]
