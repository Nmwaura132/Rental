from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import LeaseViewSet, MaintenanceRequestViewSet

router = DefaultRouter()
router.register("leases", LeaseViewSet, basename="lease")
router.register("maintenance", MaintenanceRequestViewSet, basename="maintenance")

urlpatterns = [path("", include(router.urls))]
