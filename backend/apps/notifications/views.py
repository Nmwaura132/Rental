from django.utils import timezone
from rest_framework import generics, permissions, status
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core.permissions import IsLandlord

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


MESSAGE_MAX = 300
MESSAGES_PER_DAY = 10


class MessageTenantsView(APIView):
    """
    A landlord's own message to their tenants, by SMS.

    GET  ?property=<id> | ?tenancy=<id> | neither  -> {"recipients": n}
    POST {"message", "property"? , "tenancy"?}     -> {"sent": n}

    Neither property nor tenancy means all the landlord's current tenants.
    Each SMS starts with the building's name: it arrives from a shared sender
    ID, so the name is how the tenant knows who wrote.
    """
    permission_classes = [IsLandlord]

    def _tenancies(self, params):
        from apps.tenants.models import Tenancy

        tenancies = Tenancy.objects.filter(
            status=Tenancy.Status.ACTIVE, unit__property__owner=self.request.user
        ).select_related("tenant", "unit__property")
        if params.get("tenancy"):
            return tenancies.filter(pk=params["tenancy"])
        if params.get("property"):
            return tenancies.filter(unit__property_id=params["property"])
        return tenancies

    def get(self, request):
        return Response({"recipients": self._tenancies(request.query_params).count()})

    def post(self, request):
        from django.core.cache import cache

        from .tasks import send_sms

        message = " ".join(str(request.data.get("message", "")).split())
        if not message:
            return Response({"error": "Write the message first."}, status=status.HTTP_400_BAD_REQUEST)
        if len(message) > MESSAGE_MAX:
            return Response(
                {"error": f"Keep it to {MESSAGE_MAX} characters."}, status=status.HTTP_400_BAD_REQUEST
            )
        tenancies = list(self._tenancies(request.data))
        if not tenancies:
            return Response({"error": "No current tenants to send to."}, status=status.HTTP_400_BAD_REQUEST)

        # WHY a daily cap: every message is paid SMS to every tenant, and a
        # slip of the thumb should not be able to repeat that indefinitely.
        key = f"message-tenants:{request.user.pk}:{timezone.localdate()}"
        cache.add(key, 0, timeout=24 * 3600)
        if cache.incr(key) > MESSAGES_PER_DAY:
            return Response(
                {"error": f"That is {MESSAGES_PER_DAY} messages today; try again tomorrow."},
                status=status.HTTP_429_TOO_MANY_REQUESTS,
            )

        for tenancy in tenancies:
            send_sms.delay(tenancy.tenant_id, f"{tenancy.unit.property.name}: {message}")
        return Response({"sent": len(tenancies)})
