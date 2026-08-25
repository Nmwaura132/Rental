from django.utils import timezone
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from .models import Notification
from .serializers import NotificationSerializer


class NotificationListView(generics.ListAPIView):
    serializer_class = NotificationSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = Notification.objects.none()  # for drf-spectacular schema introspection

    def get_queryset(self):
        return Notification.objects.filter(recipient=self.request.user)


class UnreadCountView(APIView):
    """How many notifications the user has not opened yet.

    Drives the bell badge, which until now was drawn unconditionally and so
    told every user they had something waiting, forever.
    """

    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        return Response(
            {
                "unread": Notification.objects.filter(
                    recipient=request.user, read_at__isnull=True
                ).count()
            }
        )


class MarkReadView(APIView):
    """Mark the user's notifications read.

    Scoped to the requester on both paths, so an id from someone else's inbox
    simply matches nothing rather than being marked on their behalf.
    """

    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        unread = Notification.objects.filter(
            recipient=request.user, read_at__isnull=True
        )

        ids = request.data.get("ids")
        if ids is not None:
            if not isinstance(ids, list):
                return Response(
                    {"error": "ids must be a list of notification ids."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            unread = unread.filter(id__in=ids)

        marked = unread.update(read_at=timezone.now())
        return Response({"marked_read": marked})
