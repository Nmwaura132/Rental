from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import TenancyViewSet, MaintenanceRequestViewSet

router = DefaultRouter()
router.register("tenancies", TenancyViewSet, basename="tenancy")
router.register("maintenance", MaintenanceRequestViewSet, basename="maintenance")

urlpatterns = [path("", include(router.urls))]
